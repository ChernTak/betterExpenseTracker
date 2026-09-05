import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/constants/api_endpoints.dart';
import '../features/expense/data/datasources/vendor_cache_dao.dart';
import 'auth_service.dart';

/// Where a suggested category came from, so the UI knows whether to flag it for review.
class CategorySuggestion {
  final String category;
  final double confidence;
  final bool needsReview;
  final String source; // 'cache' | 'keyword' | 'embedding' | 'fallback'

  const CategorySuggestion({
    required this.category,
    required this.confidence,
    required this.needsReview,
    required this.source,
  });
}

/// Suggests a spending category for merchant text (manual/voice/OCR): cache lookup, then backend classify on a miss, caching the result.
class AutoCategorizationService {
  static const double _confidenceThreshold = 0.75;

  final VendorCacheDao _cache;
  final AuthService _authService;

  AutoCategorizationService({VendorCacheDao? cache, AuthService? authService})
    : _cache = cache ?? VendorCacheDao(),
      _authService = authService ?? AuthService();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _authService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// [source] ('manual', 'voice', 'ocr') is just for logging/display — doesn't affect resolution order.
  Future<CategorySuggestion> categorize(
    String merchantText, {
    String source = 'manual',
  }) async {
    final trimmed = merchantText.trim();
    if (trimmed.isEmpty) {
      return const CategorySuggestion(
        category: 'other',
        confidence: 0,
        needsReview: true,
        source: 'fallback',
      );
    }

    final cached = await _cache.lookup(trimmed);
    if (cached != null) {
      final confidence = (cached['confidence'] as num).toDouble();
      return CategorySuggestion(
        category: cached['category'] as String,
        confidence: confidence,
        needsReview: confidence < _confidenceThreshold,
        source: 'cache',
      );
    }

    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.expenseCategorize()),
        headers: await _authHeaders(),
        body: jsonEncode({'text': trimmed}),
      );

      if (response.statusCode != 200) {
        throw Exception('Categorize failed (status ${response.statusCode})');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final category = body['category'] as String? ?? 'other';
      final confidence = (body['confidence'] as num?)?.toDouble() ?? 0;
      final backendSource = body['source'] as String? ?? 'embedding';

      await _cache.upsert(trimmed, category, confidence, backendSource);

      return CategorySuggestion(
        category: category,
        confidence: confidence,
        needsReview: confidence < _confidenceThreshold,
        source: backendSource,
      );
    } catch (_) {
      // Offline or backend unavailable — degrade gracefully instead of
      // blocking expense entry on a categorization call.
      return const CategorySuggestion(
        category: 'other',
        confidence: 0,
        needsReview: true,
        source: 'fallback',
      );
    }
  }

  /// Writes a user correction straight to the local cache, without waiting on the backend to relearn.
  Future<void> recordCorrection(String merchantText, String category) async {
    final trimmed = merchantText.trim();
    if (trimmed.isEmpty) return;
    await _cache.overrideCategory(trimmed, category);
  }
}
