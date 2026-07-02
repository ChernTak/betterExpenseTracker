import 'package:flutter/material.dart';
import 'app_colors.dart';

// Matches the backend's expense_category enum (000_extensions_enums.sql)
const List<String> kExpenseCategories = [
  'food_dining',
  'transport',
  'shopping',
  'groceries',
  'entertainment',
  'health_medical',
  'utilities',
  'education',
  'travel',
  'personal_care',
  'subscription',
  'investment',
  'other',
];

const List<String> kPaymentMethods = [
  'cash',
  'debit_card',
  'credit_card',
  'e_wallet',
  'bank_transfer',
];

String formatCategoryLabel(String raw) {
  return raw
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

IconData categoryIcon(String category) {
  switch (category) {
    case 'food_dining':
      return Icons.restaurant;
    case 'transport':
      return Icons.directions_bus;
    case 'shopping':
      return Icons.shopping_bag;
    case 'groceries':
      return Icons.local_grocery_store;
    case 'entertainment':
      return Icons.movie;
    case 'health_medical':
      return Icons.medical_services;
    case 'utilities':
      return Icons.bolt;
    case 'education':
      return Icons.school;
    case 'travel':
      return Icons.flight;
    case 'personal_care':
      return Icons.spa;
    case 'subscription':
      return Icons.subscriptions;
    case 'investment':
      return Icons.trending_up;
    default:
      return Icons.receipt_long;
  }
}

Color categoryColor(String category) {
  switch (category) {
    case 'food_dining':
      return const Color(0xFFE58A3B);
    case 'transport':
      return const Color(0xFF3B82C4);
    case 'shopping':
      return const Color(0xFF9B59B6);
    case 'groceries':
      return const Color(0xFF2FA84F);
    case 'entertainment':
      return const Color(0xFFD64545);
    case 'health_medical':
      return const Color(0xFF35A79C);
    case 'utilities':
      return const Color(0xFFB8860B);
    case 'education':
      return const Color(0xFF4C6EF5);
    case 'travel':
      return const Color(0xFF00A8A8);
    case 'personal_care':
      return const Color(0xFFE066A6);
    case 'subscription':
      return const Color(0xFF7C6EF5);
    case 'investment':
      return AppColors.primary;
    default:
      return AppColors.textSecondary;
  }
}
