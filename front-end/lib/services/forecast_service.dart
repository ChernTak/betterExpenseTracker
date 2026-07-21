import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/constants/api_endpoints.dart';
import 'auth_service.dart';

/// Service layer for the end-of-month spend forecast (Insights tab).
///
/// Fetches the on-demand prediction the backend computes from expense
/// history and this month's budgets: projected month-end total, fixed bills
/// still due, and today's "safe-to-spend" allowance.
class ForecastService {
  final _authService = AuthService();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _authService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/insights/forecast
  Future<Map<String, dynamic>> fetchForecast() async {
    try {
      final response = await http.get(
        Uri.parse(ApiEndpoints.insightsForecast()),
        headers: await _authHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception(
          'Failed to fetch forecast (status ${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Error fetching forecast: $e');
    }
  }

  /// POST /api/insights/predictions — logs an on-device Tier B prediction
  /// for later accuracy evaluation (ai/evaluate_tier_b.py). Fire-and-forget:
  /// failures here shouldn't surface to the user or block the Insights tab.
  Future<void> logPrediction({
    required int month,
    required int year,
    required double p10,
    required double p50,
    required double p90,
    required String modelVersion,
  }) async {
    try {
      await http.post(
        Uri.parse(ApiEndpoints.insightsPredictions()),
        headers: await _authHeaders(),
        body: jsonEncode({
          'month': month,
          'year': year,
          'p10': p10,
          'p50': p50,
          'p90': p90,
          'modelVersion': modelVersion,
        }),
      );
    } catch (_) {
      // best-effort only
    }
  }
}
