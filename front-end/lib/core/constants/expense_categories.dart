const List<String> kPaymentMethods = [
  'cash',
  'debit_card',
  'credit_card',
  'e_wallet',
  'bank_transfer',
];

// Used as a display fallback for any raw category/payment-method key that
// doesn't otherwise have a proper label (e.g. CategoryItem.fallback in
// category_service.dart).
String formatCategoryLabel(String raw) {
  return raw
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
