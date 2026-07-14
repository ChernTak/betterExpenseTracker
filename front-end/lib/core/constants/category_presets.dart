import 'package:flutter/material.dart';

/// Curated icon/color choices offered when adding or editing a category
/// (Manage Categories screen) — a fixed grid rather than a full icon search
/// or color wheel, so every category (default or custom) stays visually
/// consistent with the rest of the app. Keys must match the backend's
/// ICON_PRESET_KEYS/COLOR_PRESETS (back-end/src/config/categories.js)
/// exactly, since the backend validates against the same list.
const Map<String, IconData> kCategoryIconPresets = {
  'restaurant': Icons.restaurant,
  'directions_bus': Icons.directions_bus,
  'shopping_bag': Icons.shopping_bag,
  'local_grocery_store': Icons.local_grocery_store,
  'movie': Icons.movie,
  'medical_services': Icons.medical_services,
  'bolt': Icons.bolt,
  'school': Icons.school,
  'flight': Icons.flight,
  'spa': Icons.spa,
  'subscriptions': Icons.subscriptions,
  'trending_up': Icons.trending_up,
  'receipt_long': Icons.receipt_long,
  'pets': Icons.pets,
  'home': Icons.home,
  'fitness_center': Icons.fitness_center,
  'card_giftcard': Icons.card_giftcard,
  'directions_car': Icons.directions_car,
  'local_cafe': Icons.local_cafe,
  'phone_android': Icons.phone_android,
  'child_care': Icons.child_care,
  'sports_esports': Icons.sports_esports,
  'savings': Icons.savings,
  'checkroom': Icons.checkroom,
  'build': Icons.build,
  'pool': Icons.pool,
  'local_bar': Icons.local_bar,
  'cake': Icons.cake,
  'park': Icons.park,
  'work': Icons.work,
  'favorite': Icons.favorite,
  'star': Icons.star,
  'category': Icons.category,
};

const List<String> kCategoryColorPresets = [
  '#E58A3B',
  '#3B82C4',
  '#9B59B6',
  '#2FA84F',
  '#D64545',
  '#35A79C',
  '#B8860B',
  '#4C6EF5',
  '#00A8A8',
  '#E066A6',
  '#7C6EF5',
  '#12463A',
  '#8B8F97',
  '#FF6F61',
  '#6B8E23',
  '#C2185B',
  '#009688',
  '#5D4037',
  '#455A64',
  '#FFA000',
];

/// Icon shown for a category key with no matching preset (e.g. historical
/// data pointing at a since-deleted category) — never actually assignable
/// through the picker, since every category is created with one of the
/// presets above.
const IconData kFallbackCategoryIcon = Icons.receipt_long;

Color hexToColor(String hex) {
  final buffer = StringBuffer();
  if (hex.length == 7) buffer.write('ff');
  buffer.write(hex.replaceFirst('#', ''));
  return Color(int.parse(buffer.toString(), radix: 16));
}

String colorToHex(Color color) {
  return '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
