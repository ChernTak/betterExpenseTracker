import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import '../../features/expense/data/datasources/ocr_datasource.dart';
import 'bpe_tokenizer.dart';
import 'image_preprocessor.dart';
import 'receipt_field_extractor.dart';
import 'receipt_ner_input_builder.dart';
import 'receipt_ner_model_loader.dart';

/// Runs the on-device receipt NER model (LayoutLMv3) end to end: tokenize +
/// preprocess (via [ReceiptNerInputBuilder]) -> TFLite inference -> argmax ->
/// word-level BIO tags -> field text (via [ReceiptFieldExtractor]).
class ReceiptNerService {
  final Interpreter _interpreter;
  final BpeTokenizer _tokenizer;

  ReceiptNerService(this._interpreter, this._tokenizer);

  /// Loads everything needed to run on-device extraction (the OTA/cached
  /// model via [ReceiptNerModelLoader] plus the tokenizer's bundled vocab),
  /// or returns null if the model isn't available yet (never downloaded, or
  /// download/load failed) — the caller (see plan Stage 6) should treat a
  /// null result exactly like "v3 found nothing" and rely on the backend
  /// regex parser instead.
  static BpeTokenizer? _cachedTokenizer;

  static Future<ReceiptNerService?> create() async {
    final interpreter = await ReceiptNerModelLoader().loadInterpreter();
    if (interpreter == null) return null;
    // Vocab/merges parsing rebuilds a 50265-entry rank map — cache it across
    // scans rather than redoing that work every time (the interpreter is
    // already cached the same way, inside ReceiptNerModelLoader).
    final tokenizer = _cachedTokenizer ??= await BpeTokenizer.load();
    return ReceiptNerService(interpreter, tokenizer);
  }

  /// Runs the full pipeline for one scanned receipt photo. [imageBytes] is
  /// the same photo [page]'s words/boxes were recognized from.
  ReceiptNerFields extractFields({
    required RecognizedPage page,
    required Uint8List imageBytes,
  }) {
    final pixelValues = ImagePreprocessor.preprocessBytes(imageBytes);
    final input = ReceiptNerInputBuilder.build(
      page: page,
      tokenizer: _tokenizer,
      pixelValues: pixelValues,
    );

    final logits = _runInference(input);
    final wordTags = ReceiptFieldExtractor.predictWordTags(input, logits);
    return ReceiptFieldExtractor.groupFields(input.words, wordTags);
  }

  /// Maps each of the model's 4 named inputs to its actual runtime tensor
  /// index via [Interpreter.getInputIndex] rather than a hardcoded position —
  /// confirmed via a real `.tflite` inspection that the TFLite converter does
  /// **not** preserve the `input_signature` declaration order (pixel_values
  /// ended up at index 0, attention_mask at 1, bbox at 2, input_ids at 3),
  /// so relying on declaration order would silently feed tensors to the
  /// wrong input if a future retrain/reconversion reorders them again.
  List<List<double>> _runInference(ReceiptNerInput input) {
    final ordered = List<Object?>.filled(4, null);
    ordered[_interpreter.getInputIndex('serving_default_input_ids:0')] = input.inputIds;
    ordered[_interpreter.getInputIndex('serving_default_attention_mask:0')] = input.attentionMask;
    ordered[_interpreter.getInputIndex('serving_default_bbox:0')] = input.bbox;
    ordered[_interpreter.getInputIndex('serving_default_pixel_values:0')] = input.pixelValues;

    final output = List.generate(
      1,
      (_) => List.generate(
        ReceiptNerInputBuilder.maxLength,
        (_) => List.filled(ReceiptFieldExtractor.labels.length, 0.0),
      ),
    );
    _interpreter.runForMultipleInputs(ordered.cast<Object>(), {0: output});
    return output[0];
  }
}
