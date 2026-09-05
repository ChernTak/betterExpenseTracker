import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/constants/api_endpoints.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/category_presets.dart';
import '../core/constants/expense_categories.dart' show formatCategoryLabel;
import 'auth_service.dart';

/// A single category row, resolved to Flutter-renderable icon/color so
/// screens never deal with the raw icon-key/hex strings themselves.
class CategoryItem {
  final String id;
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  final String? keywords;
  final bool isProtected;

  const CategoryItem({
    required this.id,
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
    this.keywords,
    this.isProtected = false,
  });

  factory CategoryItem.fromJson(Map<String, dynamic> json) {
    final iconKey = json['icon'] as String?;
    final hex = json['color'] as String?;
    return CategoryItem(
      id: json['category_id'] as String,
      key: json['key'] as String,
      label: json['label'] as String,
      icon: kCategoryIconPresets[iconKey] ?? kFallbackCategoryIcon,
      color: hex != null ? hexToColor(hex) : AppColors.textSecondary,
      keywords: json['keywords'] as String?,
      isProtected: json['is_protected'] as bool? ?? false,
    );
  }

  /// For a category key with no matching row (should be rare — deleting a category reassigns its expenses to 'other').
  factory CategoryItem.fallback(String key) => CategoryItem(
    id: '',
    key: key,
    label: formatCategoryLabel(key),
    icon: kFallbackCategoryIcon,
    color: AppColors.textSecondary,
  );
}

/// Categories feature (self-serve add/remove/reorder); keeps a static in-memory cache for synchronous lookups after the first fetch.
class CategoryService {
  final _authService = AuthService();

  static List<CategoryItem> _cache = [];
  static List<CategoryItem> get cached => _cache;

  static CategoryItem lookup(String key) {
    for (final category in _cache) {
      if (category.key == key) return category;
    }
    return CategoryItem.fallback(key);
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await _authService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/categories — ordered by the user's sort_order.
  Future<List<CategoryItem>> fetchCategories() async {
    try {
      final response = await http.get(Uri.parse(ApiEndpoints.categories), headers: await _authHeaders());

      if (response.statusCode == 200) {
        final list = (jsonDecode(response.body) as List<dynamic>)
            .map((e) => CategoryItem.fromJson(e as Map<String, dynamic>))
            .toList();
        _cache = list;
        return list;
      } else {
        throw Exception(
          'Failed to fetch categories (status ${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Error fetching categories: $e');
    }
  }

  /// POST /api/categories — server derives a unique key from [label].
  Future<CategoryItem> createCategory({
    required String label,
    required String icon,
    required String color,
    String? keywords,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.categories),
        headers: await _authHeaders(),
        body: jsonEncode({
          'label': label,
          'icon': icon,
          'color': color,
          if (keywords != null && keywords.trim().isNotEmpty) 'keywords': keywords.trim(),
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 201) {
        return CategoryItem.fromJson(body);
      } else {
        throw Exception(body['message'] ?? 'Failed to create category');
      }
    } catch (e) {
      throw Exception('Error creating category: $e');
    }
  }

  /// PUT /api/categories/:id — label/icon/color/keywords only; key is immutable.
  Future<CategoryItem> updateCategory(
    String categoryId, {
    String? label,
    String? icon,
    String? color,
    String? keywords,
  }) async {
    final trimmedKeywords = keywords?.trim();
    try {
      final response = await http.put(
        Uri.parse(ApiEndpoints.categoryUpdate(categoryId)),
        headers: await _authHeaders(),
        body: jsonEncode({
          'label': ?label,
          'icon': ?icon,
          'color': ?color,
          'keywords': ?trimmedKeywords,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return CategoryItem.fromJson(body);
      } else {
        throw Exception(body['message'] ?? 'Failed to update category');
      }
    } catch (e) {
      throw Exception('Error updating category: $e');
    }
  }

  /// DELETE /api/categories/:id — backend reassigns this category's
  /// expenses to 'other' and drops any budget set for it.
  Future<void> deleteCategory(String categoryId) async {
    try {
      final response = await http.delete(
        Uri.parse(ApiEndpoints.categoryDelete(categoryId)),
        headers: await _authHeaders(),
      );

      if (response.statusCode != 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(body['message'] ?? 'Failed to delete category');
      }
    } catch (e) {
      throw Exception('Error deleting category: $e');
    }
  }

  /// PUT /api/categories/reorder — [orderedCategoryIds] is the full list of
  /// this user's category IDs in the new desired display order.
  Future<List<CategoryItem>> reorderCategories(List<String> orderedCategoryIds) async {
    try {
      final response = await http.put(
        Uri.parse(ApiEndpoints.categoryReorder()),
        headers: await _authHeaders(),
        body: jsonEncode({'orderedIds': orderedCategoryIds}),
      );

      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final list = (body as List<dynamic>)
            .map((e) => CategoryItem.fromJson(e as Map<String, dynamic>))
            .toList();
        _cache = list;
        return list;
      } else {
        throw Exception((body as Map<String, dynamic>)['message'] ?? 'Failed to reorder categories');
      }
    } catch (e) {
      throw Exception('Error reordering categories: $e');
    }
  }
}
