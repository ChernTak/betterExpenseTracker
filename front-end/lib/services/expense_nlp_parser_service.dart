/// Result of parsing a spoken expense transcript. [amount] is the only
/// field callers should treat as required — everything else is a
/// best-effort extraction that the confirmation UI lets the user fix.
class ParsedVoiceExpense {
  final double? amount;
  final String? merchantName;
  final DateTime? transactionDate;
  final String rawTranscript;

  const ParsedVoiceExpense({
    required this.amount,
    required this.merchantName,
    required this.transactionDate,
    required this.rawTranscript,
  });

  bool get hasAmount => amount != null && amount! > 0;
}

/// On-device NLP for FR4.4 — pulls amount/merchant/date out of a spoken
/// expense transcript entirely with local regex/string matching, no
/// network call and no ML model (category is intentionally NOT extracted
/// here: AutoCategorizationService already does cache-first/backend-fallback
/// classification for Manual and OCR input, so voice reuses that same path
/// instead of a third, drifting copy of the keyword map).
class ExpenseNlpParserService {
  // Small-number words the two OS speech engines sometimes emit instead of
  // digits (Android's SpeechRecognizer does this far more than iOS's
  // SFSpeechRecognizer, which usually already normalizes to digits).
  static const Map<String, int> _units = {
    'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
    'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
    'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15,
    'sixteen': 16, 'seventeen': 17, 'eighteen': 18, 'nineteen': 19,
  };
  static const Map<String, int> _tens = {
    'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50,
    'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90,
  };
  static const Map<String, int> _scales = {'hundred': 100};

  // Keyword -> day offset from today. Longer phrases first so "the day
  // before yesterday" matches before the bare "yesterday" inside it.
  static const List<MapEntry<String, int>> _dateKeywords = [
    MapEntry('day before yesterday', -2),
    MapEntry('yesterday', -1),
    MapEntry('last night', -1),
    MapEntry('this morning', 0),
    MapEntry('this afternoon', 0),
    MapEntry('this evening', 0),
    MapEntry('tonight', 0),
    MapEntry('today', 0),
  ];

  static final RegExp _amountPattern = RegExp(
    r'(?:rm|myr|\$)?\s*(\d+(?:\.\d{1,2})?)\s*'
    r'(?:dollars?|bucks?|ringgit|cents?)?',
    caseSensitive: false,
  );

  static final RegExp _merchantPattern = RegExp(
    r"(?:\bat\b|\bfrom\b|\bin\b)\s+([a-z0-9'&\s]+?)"
    r'(?:\s+(?:today|yesterday|this|last|tonight|on)\b|$)',
    caseSensitive: false,
  );

  ParsedVoiceExpense parse(String transcript) {
    final normalized = _normalize(transcript);
    final withDigits = _convertWordNumbers(normalized);

    return ParsedVoiceExpense(
      amount: _extractAmount(withDigits),
      merchantName: _extractMerchant(withDigits),
      transactionDate: _extractDate(withDigits),
      rawTranscript: transcript.trim(),
    );
  }

  String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r"[^\w\s'.$]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Replaces number-word runs ("twelve", "twenty five") with digits so the
  /// amount regex below can match either form the speech engine returns.
  String _convertWordNumbers(String text) {
    final words = text.split(' ');
    final result = <String>[];
    var i = 0;

    while (i < words.length) {
      final parsed = _tryParseNumberPhrase(words, i);
      if (parsed != null) {
        result.add(parsed.value.toString());
        i = parsed.nextIndex;
      } else {
        result.add(words[i]);
        i++;
      }
    }
    return result.join(' ');
  }

  ({int value, int nextIndex})? _tryParseNumberPhrase(
    List<String> words,
    int start,
  ) {
    var i = start;
    int? hundreds;
    int? tensOrUnits;
    var matchedAny = false;

    if (i < words.length && _units.containsKey(words[i])) {
      final next = i + 1 < words.length ? words[i + 1] : null;
      if (next == _scales.keys.first) {
        hundreds = _units[words[i]]! * 100;
        i += 2;
        matchedAny = true;
      }
    }

    if (i < words.length && _tens.containsKey(words[i])) {
      tensOrUnits = _tens[words[i]];
      matchedAny = true;
      i++;
      if (i < words.length && _units.containsKey(words[i]) && _units[words[i]]! < 10) {
        tensOrUnits = tensOrUnits! + _units[words[i]]!;
        i++;
      }
    } else if (i < words.length && _units.containsKey(words[i])) {
      tensOrUnits = _units[words[i]];
      matchedAny = true;
      i++;
    }

    if (!matchedAny) return null;
    final total = (hundreds ?? 0) + (tensOrUnits ?? 0);
    return (value: total, nextIndex: i);
  }

  double? _extractAmount(String text) {
    final match = _amountPattern.firstMatch(text);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  String? _extractMerchant(String text) {
    final match = _merchantPattern.firstMatch(text);
    final raw = match?.group(1)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  /// Returns null (rather than defaulting to today) when no date phrase is
  /// found — the backend's createExpense already defaults transaction_date
  /// to CURRENT_DATE when omitted (see expense.model.js), so duplicating
  /// that default here would just be a second place to keep in sync.
  DateTime? _extractDate(String text) {
    for (final entry in _dateKeywords) {
      if (text.contains(entry.key)) {
        final today = DateTime.now();
        final dateOnly = DateTime(today.year, today.month, today.day);
        return dateOnly.add(Duration(days: entry.value));
      }
    }
    return null;
  }
}
