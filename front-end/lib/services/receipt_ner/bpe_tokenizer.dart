import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Byte-level BPE tokenizer for LayoutLMv3's RoBERTa tokenizer, ported from
/// the standard GPT2/RoBERTa algorithm - the same one used by
/// `ai/receipt_ner_gpu_training_v3.ipynb`'s `LayoutLMv3TokenizerFast`.
///
/// Every piece of this was verified against that real Python tokenizer
/// before being ported, not assumed:
/// - `tokenizer.json`'s config confirmed a plain `ByteLevel` pre-tokenizer
///   (`add_prefix_space: true`) + `RobertaProcessing` post-processor
///   (`<s>`/`</s>` wrapping) - the standard, unmodified scheme; fine-tuning
///   only changes model weights, never the tokenizer vocabulary.
/// - The byte-to-unicode table below is the exact 256-entry table from
///   `transformers.models.roberta.tokenization_roberta.bytes_to_unicode()`.
/// - The pre-tokenization regex below produced byte-for-byte identical
///   splits to Python's `GPT2Tokenizer.pat` on test strings including
///   currency amounts and contractions (`"RM20.80"` -> `[' RM','20','.','80']`
///   in both).
/// - Feeding a list of words (not raw text) confirmed EVERY word gets its
///   own leading space prepended before encoding (`add_prefix_space`
///   applies per-word for pre-split input), not just words after the
///   first - verified directly: `['TOTAL', ':', 'RM20.80']` tokenized to
///   `['<s>','ĠTOTAL','Ġ:','ĠRM','20','.','80','</s>']` with
///   `word_ids = [None,0,1,2,2,2,2,None]`.
class BpeTokenizer {
  static const int clsTokenId = 0; // <s>
  static const int padTokenId = 1; // <pad>
  static const int sepTokenId = 2; // </s>
  static const int unkTokenId = 3; // <unk>

  // GPT2/RoBERTa pre-tokenization regex - splits text into chunks (each
  // starting with at most one leading space) before byte-level BPE is
  // applied within each chunk independently. `unicode: true` enables the
  // \p{L}/\p{N} Unicode property escapes this pattern needs - confirmed
  // Dart's RegExp engine handles these identically to Python's `regex`
  // library for this exact pattern (see class doc above).
  static final RegExp _preTokenizeRegex = RegExp(
    r"'s|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+",
    unicode: true,
  );

  // Byte value (0-255) -> Unicode codepoint. Maps printable ASCII/Latin-1
  // bytes to themselves and remaps the "invisible"/control bytes (space,
  // newline, etc.) to otherwise-unused codepoints starting at 256, so
  // every possible byte has a distinct, visible, roundtrippable character
  // to run BPE merges over. Exact values extracted from
  // `transformers.models.roberta.tokenization_roberta.bytes_to_unicode()`,
  // not reconstructed from a description of the algorithm.
  static const List<int> _byteToUnicode = [
    256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271,
    272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287,
    288, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
    48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
    64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79,
    80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95,
    96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111,
    112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 289,
    290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305,
    306, 307, 308, 309, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321,
    322, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 323, 174, 175,
    176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191,
    192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207,
    208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223,
    224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239,
    240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255,
  ];

  final Map<String, int> _vocab; // BPE token string -> vocab id
  final Map<String, int> _bpeRanks; // "tokA tokB" -> merge priority (lower = merge first)
  final Map<String, List<int>> _encodeCache = {};

  BpeTokenizer._(this._vocab, this._bpeRanks);

  /// Loads `vocab.json` (token -> id map) and `merges.txt` (ordered merge
  /// rules, one "tokA tokB" pair per line, first line is a "#version: ..."
  /// header to skip) from Flutter assets - the exact files LayoutLMv3's
  /// tokenizer saved alongside the model
  /// (`ai/saved_pytorch_model_v3/vocab.json` and `.../merges.txt`).
  static Future<BpeTokenizer> load({
    String vocabAsset = 'assets/models/receipt_ner_vocab.json',
    String mergesAsset = 'assets/models/receipt_ner_merges.txt',
  }) async {
    final vocabJson = await rootBundle.loadString(vocabAsset);
    final Map<String, dynamic> rawVocab = json.decode(vocabJson) as Map<String, dynamic>;
    final vocab = rawVocab.map((key, value) => MapEntry(key, value as int));

    final mergesText = await rootBundle.loadString(mergesAsset);
    final lines = mergesText.split('\n').where((line) => line.trim().isNotEmpty).toList();
    final mergeLines = lines.isNotEmpty && lines.first.startsWith('#version') ? lines.sublist(1) : lines;
    final ranks = <String, int>{};
    for (var i = 0; i < mergeLines.length; i++) {
      ranks[mergeLines[i].trim()] = i;
    }

    return BpeTokenizer._(vocab, ranks);
  }

  /// Applies byte-level BPE to one pre-tokenized chunk (already
  /// regex-split, with its leading space if any) - encodes each UTF-8 byte
  /// to its mapped character, then repeatedly merges the highest-priority
  /// (lowest-rank) adjacent pair until no known merge applies, matching
  /// the standard BPE algorithm exactly.
  List<int> _bpeEncodeChunk(String chunk) {
    final cached = _encodeCache[chunk];
    if (cached != null) return cached;

    final bytes = utf8.encode(chunk);
    var symbols = <String>[for (final b in bytes) String.fromCharCode(_byteToUnicode[b])];

    if (symbols.length > 1) {
      while (true) {
        int? bestRank;
        var bestIndex = -1;
        for (var i = 0; i < symbols.length - 1; i++) {
          final rank = _bpeRanks['${symbols[i]} ${symbols[i + 1]}'];
          if (rank != null && (bestRank == null || rank < bestRank)) {
            bestRank = rank;
            bestIndex = i;
          }
        }
        if (bestIndex == -1) break; // no known merge left - done

        symbols = [
          ...symbols.sublist(0, bestIndex),
          symbols[bestIndex] + symbols[bestIndex + 1],
          ...symbols.sublist(bestIndex + 2),
        ];
      }
    }

    final ids = symbols.map((s) => _vocab[s] ?? unkTokenId).toList();
    _encodeCache[chunk] = ids;
    return ids;
  }

  /// Encodes one word with its own leading space prepended (confirmed
  /// per-word `add_prefix_space` behavior - see class doc), returning its
  /// subtoken vocab ids in order.
  List<int> encodeWord(String word) {
    final withLeadingSpace = ' $word';
    final ids = <int>[];
    for (final match in _preTokenizeRegex.allMatches(withLeadingSpace)) {
      ids.addAll(_bpeEncodeChunk(match.group(0)!));
    }
    return ids;
  }

  /// Encodes a list of already word-split text (e.g. from ML Kit) into
  /// model-ready input_ids, wrapped with `<s>`/`</s>` (matching
  /// `RobertaProcessing`), plus a parallel `wordIds` list (null for the
  /// two special tokens) mirroring Python's `Encoding.word_ids()` - needed
  /// downstream to map each subtoken back to its word's bounding box and,
  /// for the first subtoken of a word, its predicted label.
  ({List<int> inputIds, List<int?> wordIds}) encodeWords(List<String> words) {
    final inputIds = <int>[clsTokenId];
    final wordIds = <int?>[null];

    for (var wordIndex = 0; wordIndex < words.length; wordIndex++) {
      final subwordIds = encodeWord(words[wordIndex]);
      inputIds.addAll(subwordIds);
      wordIds.addAll(List.filled(subwordIds.length, wordIndex));
    }

    inputIds.add(sepTokenId);
    wordIds.add(null);
    return (inputIds: inputIds, wordIds: wordIds);
  }
}
