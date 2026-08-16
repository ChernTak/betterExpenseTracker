/// Turns the model's raw span text (e.g. `"RM20.80"`, `"12/03/2024"`) into
/// the typed values the form fields need. Mirrors
/// `back-end/src/services/ocr.service.js`'s `extractAmount`/`extractDate`
/// conventions deliberately, not by coincidence — v3 and the backend regex
/// parser are meant to agree on the same receipt when both find a value
/// (see plan Stage 6), so they need the same day/month-first assumption
/// (Malaysian receipts print DD/MM/YYYY) and the same "strip everything but
/// digits and the decimal point" amount cleanup.
class ReceiptFieldNormalizer {
  static const List<String> _months = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun',
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];

  /// Strips everything but digits and `.` (matching
  /// `ai/receipt_ner_model_test.ipynb`'s own `normalize_amount`, used there
  /// to score the model's extractions — reusing the same rule here keeps
  /// "the model got TOTAL right" consistent between evaluation and
  /// production) and parses what's left. Returns null if nothing usable
  /// remains (caller falls back to the backend regex's amount).
  static double? parseAmount(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  /// Tries the same 3 receipt date shapes as `ocr.service.js#extractDate`,
  /// in the same priority order, and normalizes to ISO `yyyy-MM-dd`. Returns
  /// null if none match (caller falls back to the backend regex's date).
  static String? parseDateToIso(String text) {
    final isoMatch = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
    if (isoMatch != null) {
      final iso = '${isoMatch[1]}-${isoMatch[2]}-${isoMatch[3]}';
      if (DateTime.tryParse(iso) != null) return iso;
    }

    final slashMatch = RegExp(r'(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})').firstMatch(text);
    if (slashMatch != null) {
      final day = slashMatch[1]!.padLeft(2, '0');
      final month = slashMatch[2]!.padLeft(2, '0');
      final year = slashMatch[3]!;
      final iso = '$year-$month-$day';
      if (DateTime.tryParse(iso) != null) return iso;
    }

    final namedMatch = RegExp(r'(\d{1,2})\s+([A-Za-z]{3,})\s+(\d{4})').firstMatch(text);
    if (namedMatch != null) {
      final monthName = namedMatch[2]!.toLowerCase().substring(0, 3);
      final monthIndex = _months.indexOf(monthName);
      if (monthIndex != -1) {
        final day = namedMatch[1]!.padLeft(2, '0');
        final month = (monthIndex + 1).toString().padLeft(2, '0');
        final year = namedMatch[3]!;
        final iso = '$year-$month-$day';
        if (DateTime.tryParse(iso) != null) return iso;
      }
    }

    return null;
  }
}
