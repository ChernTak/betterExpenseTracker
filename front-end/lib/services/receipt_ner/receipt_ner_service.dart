import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import '../../features/expense/data/datasources/ocr_datasource.dart';
import 'bpe_tokenizer.dart';
import 'image_preprocessor.dart';
import 'receipt_field_extractor.dart';
import 'receipt_ner_input_builder.dart';
import 'receipt_ner_model_loader.dart';

/// Runs the on-device receipt NER model (LayoutLMv3) end to end: tokenize + preprocess -> TFLite inference -> argmax -> word-level BIO tags -> field text.
class ReceiptNerService {
  final Interpreter _interpreter;
  final BpeTokenizer _tokenizer;

  ReceiptNerService(this._interpreter, this._tokenizer);

  /// Loads the OTA/cached model plus tokenizer; returns null if the model isn't available yet, and the caller should fall back to the backend regex parser.
  static BpeTokenizer? _cachedTokenizer;

  static Future<ReceiptNerService?> create() async {
    final interpreter = await ReceiptNerModelLoader().loadInterpreter();
    if (interpreter == null) return null;
    // Cache the tokenizer (50265-entry rank map) across scans instead of rebuilding it every time.
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

  /// Maps each input by name via [Interpreter.getInputIndex] rather than a hardcoded position — the TFLite converter doesn't preserve declaration order, so a fixed index would silently break on reconversion.
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
