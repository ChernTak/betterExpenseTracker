import 'dart:typed_data';
import 'dart:ui' show Rect;

import '../../features/expense/data/datasources/ocr_datasource.dart';
import 'bpe_tokenizer.dart';
import 'image_preprocessor.dart';

/// One word plus the normalized [0,1000]-scale box the model was trained on
/// (see [ReceiptNerInputBuilder._normalizeBox]) — kept around post-tokenization
/// so Stage 4's field extraction (`extract_spans`/`group_fields`, ported from
/// `ai/receipt_ner_model_test.ipynb`) has the same word-level boxes Python
/// used for its largest-box tie-break, not just token-level data.
class ReceiptNerWord {
  final String text;
  final List<int> normalizedBox;

  const ReceiptNerWord({required this.text, required this.normalizedBox});
}

/// The 4 fixed-shape tensors the exported `.tflite` model's `InferenceWrapper`
/// signature expects (`ai/receipt_ner_gpu_training_v3.ipynb`, Cell 22):
/// `input_ids`/`attention_mask` int32 `[1, 512]`, `bbox` int32 `[1, 512, 4]`,
/// `pixel_values` float32 `[1, 3, 224, 224]` — plus the word-level data Stage 4
/// needs to turn per-token predictions back into per-field text.
class ReceiptNerInput {
  final List<List<int>> inputIds;
  final List<List<int>> attentionMask;
  final List<List<List<int>>> bbox;
  final List<List<List<List<double>>>> pixelValues;

  /// Original words, untruncated — same length as [wordBoxes]. Stage 4's
  /// word-tag reconstruction needs every word represented (defaulting to
  /// "O"), even ones truncated out of [inputIds], matching Python's
  /// `predict_word_tags` (`ai/receipt_ner_model_test.ipynb`, Cell 19), which
  /// pre-fills `word_tags = ["O"] * len(words)` before overwriting only the
  /// words that survived tokenization.
  final List<ReceiptNerWord> words;

  /// Word index for each of the 512 token slots (null for `<s>`/`</s>`/`<pad>`)
  /// — mirrors `Encoding.word_ids()`, needed to map each token's predicted
  /// label back to its word.
  final List<int?> tokenWordIds;

  const ReceiptNerInput({
    required this.inputIds,
    required this.attentionMask,
    required this.bbox,
    required this.pixelValues,
    required this.words,
    required this.tokenWordIds,
  });
}

/// Assembles ML Kit word/box data + a preprocessed receipt photo into the 4
/// tensors the on-device receipt NER model (LayoutLMv3) expects. Every
/// convention here was verified against the real Python
/// `LayoutLMv3TokenizerFast`/training pipeline, not assumed:
/// - `normalize_bbox`: ported verbatim from
///   `ai/receipt_ner_gpu_training_v3.ipynb` Cell 7 — scale each coordinate to
///   0-1000 relative to the page's own pixel dimensions, via
///   `int(value * 1000 / extent)` (truncation, not rounding), clamped to
///   [0, 1000].
/// - Special-token boxes: confirmed directly against
///   `tokenizer(words, boxes=...)` output that `<s>` and `</s>` both get
///   `[0, 0, 0, 0]`, and every subtoken of a word repeats that word's whole
///   box (not split/interpolated).
/// - Truncation: confirmed `truncation=True, max_length=512` truncates
///   *content* tokens only, keeping `<s>` first and `</s>` last (a 20-word,
///   max_length=10 test truncated to `[<s>, w0(2 tok), w1(2 tok), w2(2 tok),
///   w3(2 tok), </s>]` — content cut from the end, boundary tokens intact).
/// - Padding: `<pad>` (id 1) for `input_ids`, `0` for `attention_mask`,
///   `[0, 0, 0, 0]` for `bbox` — matching `_pad_to_max_length` (Cell 23).
class ReceiptNerInputBuilder {
  static const int maxLength = 512;

  static ReceiptNerInput build({
    required RecognizedPage page,
    required BpeTokenizer tokenizer,
    required Float32List pixelValues,
  }) {
    final words = [
      for (final word in page.words)
        ReceiptNerWord(
          text: word.text,
          normalizedBox: _normalizeBox(word.boundingBox, page.imageWidth, page.imageHeight),
        ),
    ];

    final encoded = tokenizer.encodeWords([for (final w in words) w.text]);
    var tokenIds = encoded.inputIds;
    var tokenWordIds = encoded.wordIds;

    if (tokenIds.length > maxLength) {
      final contentLimit = maxLength - 2; // room left for <s> and </s>
      tokenIds = [
        tokenIds.first,
        ...tokenIds.sublist(1, 1 + contentLimit),
        BpeTokenizer.sepTokenId,
      ];
      tokenWordIds = [
        tokenWordIds.first,
        ...tokenWordIds.sublist(1, 1 + contentLimit),
        null,
      ];
    }

    final tokenBoxes = [
      for (var i = 0; i < tokenIds.length; i++)
        tokenWordIds[i] == null ? const [0, 0, 0, 0] : words[tokenWordIds[i]!].normalizedBox,
    ];

    final padLength = maxLength - tokenIds.length;
    final paddedInputIds = [...tokenIds, ...List.filled(padLength, BpeTokenizer.padTokenId)];
    final paddedAttentionMask = [...List.filled(tokenIds.length, 1), ...List.filled(padLength, 0)];
    final paddedTokenWordIds = [...tokenWordIds, ...List<int?>.filled(padLength, null)];
    final paddedBoxes = [...tokenBoxes, ...List.generate(padLength, (_) => const [0, 0, 0, 0])];

    return ReceiptNerInput(
      inputIds: [paddedInputIds],
      attentionMask: [paddedAttentionMask],
      bbox: [paddedBoxes],
      pixelValues: [_reshapePixelValues(pixelValues)],
      words: words,
      tokenWordIds: paddedTokenWordIds,
    );
  }

  static List<int> _normalizeBox(Rect box, int pageWidth, int pageHeight) {
    return [
      _scale(box.left, pageWidth),
      _scale(box.top, pageHeight),
      _scale(box.right, pageWidth),
      _scale(box.bottom, pageHeight),
    ];
  }

  static int _scale(double value, int extent) {
    if (extent <= 0) return 0;
    final scaled = (value * 1000 / extent).toInt();
    if (scaled < 0) return 0;
    if (scaled > 1000) return 1000;
    return scaled;
  }

  /// [flat] is channel-first (C, H, W), matching
  /// [ImagePreprocessor.preprocessBytes]'s output order — reshapes it into
  /// the nested-list form `Interpreter.run`/`runForMultipleInputs` expects
  /// for a `[3, 224, 224]` tensor (see `tier_b_inference_service.dart` for
  /// this codebase's established nested-list convention).
  static List<List<List<double>>> _reshapePixelValues(Float32List flat) {
    const size = ImagePreprocessor.targetSize;
    var index = 0;
    return List.generate(
      3,
      (_) => List.generate(size, (_) => List.generate(size, (_) => flat[index++])),
    );
  }
}
