import 'dart:typed_data';
import 'dart:ui' show Rect;

import '../../features/expense/data/datasources/ocr_datasource.dart';
import 'bpe_tokenizer.dart';
import 'image_preprocessor.dart';

/// One word plus its normalized [0,1000]-scale box; kept post-tokenization so field extraction has the same word-level boxes Python used for its largest-box tie-break.
class ReceiptNerWord {
  final String text;
  final List<int> normalizedBox;

  const ReceiptNerWord({required this.text, required this.normalizedBox});
}

/// The 4 fixed-shape tensors the exported `.tflite` model's `InferenceWrapper` expects (input_ids/attention_mask `[1,512]`, bbox `[1,512,4]`, pixel_values `[1,3,224,224]`), plus word-level data for turning predictions back into field text.
class ReceiptNerInput {
  final List<List<int>> inputIds;
  final List<List<int>> attentionMask;
  final List<List<List<int>>> bbox;
  final List<List<List<List<double>>>> pixelValues;

  /// Original words, untruncated — every word must be represented (defaulting to "O"), even ones truncated out of [inputIds], matching Python's `predict_word_tags` pre-fill behavior.
  final List<ReceiptNerWord> words;

  /// Word index for each of the 512 token slots (null for `<s>`/`</s>`/`<pad>`) — mirrors `Encoding.word_ids()`, maps each token's predicted label back to its word.
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

/// Assembles ML Kit word/box data + a preprocessed receipt photo into the 4 tensors LayoutLMv3 expects. Box normalization (0-1000 via truncation, not rounding), special-token boxes ([0,0,0,0] repeated per subtoken), truncation (content cut from the end, `<s>`/`</s>` kept), and padding (`<pad>`/`0`/`[0,0,0,0]`) all verified against the real Python tokenizer/training pipeline.
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

  /// Reshapes [flat] (channel-first, matching [ImagePreprocessor.preprocessBytes]'s output) into the nested-list `[3, 224, 224]` form `Interpreter.run` expects.
  static List<List<List<double>>> _reshapePixelValues(Float32List flat) {
    const size = ImagePreprocessor.targetSize;
    var index = 0;
    return List.generate(
      3,
      (_) => List.generate(size, (_) => List.generate(size, (_) => flat[index++])),
    );
  }
}
