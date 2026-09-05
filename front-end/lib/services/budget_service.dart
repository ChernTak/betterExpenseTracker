import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/constants/api_endpoints.dart';
import 'auth_service.dart';

/// Budget feature (FR3.1–FR3.5): monthly category limits, spend-vs-limit dashboard, and 60/75/90% utilisation alert history.
class BudgetService {
  final _authService = AuthService();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _authService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/budgets — current month's budgets with utilisation + totals.
  Future<Map<String, dynamic>> fetchDashboard({int? month, int? year}) async {
    try {
      final response = await http.get(
        Uri.parse(ApiEndpoints.budgetsList(month: month, year: year)),
        headers: await _authHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception(
          'Failed to fetch budgets (status ${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Error fetching budgets: $e');
    }
  }

  /// POST /api/budgets — creates the category's limit, or updates it if one
  /// already exists for this category/month.
  Future<Map<String, dynamic>> saveBudget({
    required String category,
    required double monthlyLimit,
    double? alertThreshold,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.budgets),
        headers: await _authHeaders(),
        body: jsonEncode({
          'category': category,
          'monthlyLimit': monthlyLimit,
          'alertThreshold': ?alertThreshold,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 201) {
        return body;
      } else {
        throw Exception(body['message'] ?? 'Failed to save budget');
      }
    } catch (e) {
      throw Exception('Error saving budget: $e');
    }
  }

  /// PUT /api/budgets/:id — update an existing budget's limit or threshold.
  Future<Map<String, dynamic>> updateBudget(
    String budgetId, {
    double? monthlyLimit,
    double? alertThreshold,
  }) async {
    try {
      final response = await http.put(
        Uri.parse(ApiEndpoints.budgetUpdate(budgetId)),
        headers: await _authHeaders(),
        body: jsonEncode({
          'monthlyLimit': ?monthlyLimit,
          'alertThreshold': ?alertThreshold,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return body;
      } else {
        throw Exception(body['message'] ?? 'Failed to update budget');
      }
    } catch (e) {
      throw Exception('Error updating budget: $e');
    }
  }

  /// DELETE /api/budgets/:id
  Future<void> deleteBudget(String budgetId) async {
    try {
      final response = await http.delete(
        Uri.parse(ApiEndpoints.budgetDelete(budgetId)),
        headers: await _authHeaders(),
      );

      if (response.statusCode != 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(body['message'] ?? 'Failed to delete budget');
      }
    } catch (e) {
      throw Exception('Error deleting budget: $e');
    }
  }

  /// GET /api/budgets/alerts — recent 60/75/90% threshold alerts (FR3.5).
  Future<List<dynamic>> fetchRecentAlerts({int limit = 20}) async {
    try {
      final response = await http.get(
        Uri.parse(ApiEndpoints.budgetAlerts(limit: limit)),
        headers: await _authHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      } else {
        throw Exception(
          'Failed to fetch alerts (status ${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Error fetching alerts: $e');
    }
  }
}
