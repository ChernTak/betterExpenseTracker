import 'receipt_ner_input_builder.dart';

/// One field this model predicts — empty string means "not found", which is
/// exactly the signal the caller (see plan Stage 6) uses to fall back to the
/// backend regex parser's value instead.
class ReceiptNerFields {
  final String company;
  final String date;
  final String address;
  final String total;

  const ReceiptNerFields({
    required this.company,
    required this.date,
    required this.address,
    required this.total,
  });
}

class ReceiptSpan {
  final String text;
  final List<int> box; // normalized [x0, y0, x2, y2], union of the span's words

  const ReceiptSpan(this.text, this.box);
}

/// Turns per-token model logits into field text. A direct port of
/// `predict_word_tags`/`extract_spans`/`group_fields` from
/// `ai/receipt_ner_model_test.ipynb` Cell 19 — this is the logic that took
/// TOTAL's correct rate from 17% to 91% in testing (the largest-box
/// tie-break, not just taking the first candidate), so it must stay in
/// lockstep with the Python original, not be "simplified" during the port.
///
/// Deliberately has no dependency on [Interpreter] or any model-loading
/// concern (see `receipt_ner_service.dart`) — pure input-in/text-out, so
/// this port's correctness can be verified directly against Python without
/// needing a device to run the actual TFLite model on (`tflite_flutter` has
/// no desktop binary; real inference can only be exercised on-device).
class ReceiptFieldExtractor {
  // Must exactly match `ai/receipt_parser_v3_labels.json`'s `labels` array
  // (index == the model's output class index).
  static const List<String> labels = [
    'O',
    'B-COMPANY',
    'I-COMPANY',
    'B-DATE',
    'I-DATE',
    'B-ADDRESS',
    'I-ADDRESS',
    'B-TOTAL',
    'I-TOTAL',
  ];
  static const List<String> fields = ['COMPANY', 'DATE', 'ADDRESS', 'TOTAL'];

  // Fields where a receipt can have multiple candidate spans (e.g. several
  // number-looking words tagged TOTAL) and the *largest* bounding box wins —
  // confirmed via `ai/receipt_ner_model_test.ipynb` Cell 19's `group_fields`
  // as the fix that took TOTAL's correct-match rate from 17% to 91%/39% (vs.
  // just taking the first match, which usually grabs a subtotal/tax line
  // above the real total). COMPANY/ADDRESS use the first span instead.
  static const Set<String> largestBoxFields = {'TOTAL', 'DATE'};

  /// Ports `predict_word_tags`: for each word, use its *first* subtoken's
  /// predicted label (matching how `word_ids()` + `seen_words` dedupe
  /// subtokens in the Python original); words truncated out of
  /// [ReceiptNerInput.tokenWordIds] entirely are left at the "O" default,
  /// same as Python's pre-filled `word_tags = ["O"] * len(words)`.
  static List<String> predictWordTags(ReceiptNerInput input, List<List<double>> logits) {
    final wordTags = List<String>.filled(input.words.length, 'O');
    final seenWords = <int>{};
    for (var tokenIndex = 0; tokenIndex < input.tokenWordIds.length; tokenIndex++) {
      final wordId = input.tokenWordIds[tokenIndex];
      if (wordId == null || !seenWords.add(wordId)) continue;
      wordTags[wordId] = labels[_argmax(logits[tokenIndex])];
    }
    return wordTags;
  }

  static int _argmax(List<double> values) {
    var bestIndex = 0;
    for (var i = 1; i < values.length; i++) {
      if (values[i] > values[bestIndex]) bestIndex = i;
    }
    return bestIndex;
  }

  /// Ports `group_fields`/`extract_spans` exactly, including its tie-break:
  /// for [largestBoxFields], picks the *first* span with the
  /// strictly-largest area (Python's `max(list, key=...)` semantics — a
  /// naive `List.sort` would not reproduce this, since Dart's sort isn't
  /// guaranteed stable and could pick a different span among ties).
  static ReceiptNerFields groupFields(List<ReceiptNerWord> words, List<String> wordTags) {
    final result = <String, String>{};
    for (final field in fields) {
      final spans = extractSpans(words, wordTags, field);
      if (spans.isEmpty) {
        result[field] = '';
      } else if (largestBoxFields.contains(field)) {
        result[field] = _largestByArea(spans).text;
      } else {
        result[field] = spans.first.text;
      }
    }
    return ReceiptNerFields(
      company: result['COMPANY']!,
      date: result['DATE']!,
      address: result['ADDRESS']!,
      total: result['TOTAL']!,
    );
  }

  static List<ReceiptSpan> extractSpans(List<ReceiptNerWord> words, List<String> wordTags, String field) {
    final spans = <ReceiptSpan>[];
    var i = 0;
    while (i < words.length) {
      if (wordTags[i] == 'B-$field') {
        final spanWords = [words[i].text];
        var box = words[i].normalizedBox;
        var j = i + 1;
        while (j < words.length && wordTags[j] == 'I-$field') {
          spanWords.add(words[j].text);
          box = _unionBox(box, words[j].normalizedBox);
          j++;
        }
        spans.add(ReceiptSpan(spanWords.join(' '), box));
        i = j;
      } else {
        i++;
      }
    }
    return spans;
  }

  static List<int> _unionBox(List<int> a, List<int> b) {
    return [
      a[0] < b[0] ? a[0] : b[0],
      a[1] < b[1] ? a[1] : b[1],
      a[2] > b[2] ? a[2] : b[2],
      a[3] > b[3] ? a[3] : b[3],
    ];
  }

  static int _lineArea(List<int> box) {
    final width = box[2] - box[0];
    final height = box[3] - box[1];
    return (width > 0 ? width : 0) + (height > 0 ? height : 0);
  }

  static ReceiptSpan _largestByArea(List<ReceiptSpan> spans) {
    var best = spans[0];
    var bestArea = _lineArea(best.box);
    for (var i = 1; i < spans.length; i++) {
      final area = _lineArea(spans[i].box);
      if (area > bestArea) {
        best = spans[i];
        bestArea = area;
      }
    }
    return best;
  }
}
