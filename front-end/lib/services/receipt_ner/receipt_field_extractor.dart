import 'receipt_ner_input_builder.dart';

/// One field this model predicts — empty string signals "not found" so the caller falls back to the backend regex parser.
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

/// Turns per-token model logits into field text. Direct port of `predict_word_tags`/`extract_spans`/`group_fields` from `ai/receipt_ner_model_test.ipynb` Cell 19 (the largest-box tie-break took TOTAL's accuracy from 17% to 91%, so keep in lockstep with the Python original). Deliberately has no [Interpreter]/model-loading dependency so it's testable against Python without on-device TFLite inference.
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

  // For these fields, multiple candidate spans can occur, so the largest bounding box wins (took TOTAL's accuracy from 17% to 91% vs. just taking the first match). COMPANY/ADDRESS use the first span instead.
  static const Set<String> largestBoxFields = {'TOTAL', 'DATE'};

  /// Ports `predict_word_tags`: uses each word's *first* subtoken's predicted label; words truncated out of [ReceiptNerInput.tokenWordIds] stay at the "O" default, matching the Python original.
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

  /// Ports `group_fields`/`extract_spans`: for [largestBoxFields], picks the first strictly-largest-area span (Python's `max(key=...)` semantics — a plain `List.sort` isn't guaranteed stable and could pick differently among ties).
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
