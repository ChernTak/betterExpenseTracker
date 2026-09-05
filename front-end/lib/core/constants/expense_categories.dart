const List<String> kPaymentMethods = [
  'cash',
  'debit_card',
  'credit_card',
  'e_wallet',
  'bank_transfer',
];

// Display fallback for a raw category/payment-method key with no proper label (see CategoryItem.fallback).
String formatCategoryLabel(String raw) {
  return raw
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
