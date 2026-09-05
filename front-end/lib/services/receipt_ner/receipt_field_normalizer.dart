/// Turns the model's raw span text into typed form values. Deliberately mirrors `back-end/src/services/ocr.service.js`'s extractAmount/extractDate conventions (DD/MM/YYYY assumption, digit-only amount cleanup) so the model and backend regex parser agree when both find a value.
class ReceiptFieldNormalizer {
  static const List<String> _months = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun',
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];

  /// Strips everything but digits and `.` (matching the notebook's own `normalize_amount` used to score the model, keeping eval and production consistent) and parses what's left. Null if nothing usable remains.
  static double? parseAmount(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  /// Tries the same 3 date shapes as `ocr.service.js#extractDate`, same priority order, normalized to ISO `yyyy-MM-dd`. Null if none match.
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
