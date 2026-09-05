import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/constants/api_endpoints.dart';
import 'auth_service.dart';

/// Tier C: logs manual income events (no bank integration); payday prediction is server-side via GET /api/insights/forecast's `expectedIncome`, not fetched here.
class IncomeService {
  final _authService = AuthService();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _authService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// POST /api/income
  Future<Map<String, dynamic>> logIncome({
    required double amount,
    String? source,
    DateTime? receivedDate,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.income),
        headers: await _authHeaders(),
        body: jsonEncode({
          'amount': amount,
          if (source != null && source.isNotEmpty) 'source': source,
          // receivedDate is a DATE-only column server-side — trim the time
          // component toIso8601String() would otherwise include.
          if (receivedDate != null)
            'receivedDate': receivedDate.toIso8601String().substring(0, 10),
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 201) {
        return body;
      } else {
        throw Exception(body['message'] ?? 'Failed to log income');
      }
    } catch (e) {
      throw Exception('Error logging income: $e');
    }
  }

  /// GET /api/income — last 6 months of logged income.
  Future<List<dynamic>> fetchIncomeHistory() async {
    try {
      final response = await http.get(
        Uri.parse(ApiEndpoints.income),
        headers: await _authHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      } else {
        throw Exception(
          'Failed to fetch income history (status ${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Error fetching income history: $e');
    }
  }

  /// PUT /api/income/:id
  Future<Map<String, dynamic>> updateIncome(
    String incomeId, {
    double? amount,
    String? source,
    DateTime? receivedDate,
  }) async {
    try {
      final response = await http.put(
        Uri.parse(ApiEndpoints.incomeUpdate(incomeId)),
        headers: await _authHeaders(),
        body: jsonEncode({
          'amount': ?amount,
          'source': ?source,
          if (receivedDate != null)
            'receivedDate': receivedDate.toIso8601String().substring(0, 10),
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return body;
      } else {
        throw Exception(body['message'] ?? 'Failed to update income entry');
      }
    } catch (e) {
      throw Exception('Error updating income entry: $e');
    }
  }

  /// DELETE /api/income/:id
  Future<void> deleteIncome(String incomeId) async {
    try {
      final response = await http.delete(
        Uri.parse(ApiEndpoints.incomeDelete(incomeId)),
        headers: await _authHeaders(),
      );

      if (response.statusCode != 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(body['message'] ?? 'Failed to delete income entry');
      }
    } catch (e) {
      throw Exception('Error deleting income entry: $e');
    }
  }
}
