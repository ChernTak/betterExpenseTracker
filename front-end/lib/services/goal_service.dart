import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/constants/api_endpoints.dart';
import 'auth_service.dart';

/// Saving Goals: user-initiated cumulative savings target, distinct from Wishlist which is reactive/nudge-triggered.
class GoalService {
  final _authService = AuthService();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _authService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// POST /api/goals
  Future<Map<String, dynamic>> createGoal({
    required String goalName,
    required double targetAmount,
    DateTime? deadlineDate,
    int? priority,
    String? notes,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.goals),
        headers: await _authHeaders(),
        body: jsonEncode({
          'goalName': goalName,
          'targetAmount': targetAmount,
          if (deadlineDate != null)
            'deadlineDate': deadlineDate.toIso8601String().substring(0, 10),
          'priority': ?priority,
          'notes': ?notes,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 201) {
        return body;
      } else {
        throw Exception(body['message'] ?? 'Failed to create goal');
      }
    } catch (e) {
      throw Exception('Error creating goal: $e');
    }
  }

  /// GET /api/goals
  Future<List<dynamic>> fetchGoals() async {
    try {
      final response = await http.get(
        Uri.parse(ApiEndpoints.goals),
        headers: await _authHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      } else {
        throw Exception(
          'Failed to fetch goals (status ${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Error fetching goals: $e');
    }
  }

  /// PUT /api/goals/:id
  Future<Map<String, dynamic>> updateGoal(
    String goalId, {
    String? goalName,
    double? targetAmount,
    DateTime? deadlineDate,
    String? status,
    int? priority,
    String? notes,
  }) async {
    try {
      final response = await http.put(
        Uri.parse(ApiEndpoints.goalUpdate(goalId)),
        headers: await _authHeaders(),
        body: jsonEncode({
          'goalName': ?goalName,
          'targetAmount': ?targetAmount,
          if (deadlineDate != null)
            'deadlineDate': deadlineDate.toIso8601String().substring(0, 10),
          'status': ?status,
          'priority': ?priority,
          'notes': ?notes,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return body;
      } else {
        throw Exception(body['message'] ?? 'Failed to update goal');
      }
    } catch (e) {
      throw Exception('Error updating goal: $e');
    }
  }

  /// DELETE /api/goals/:id
  Future<void> deleteGoal(String goalId) async {
    try {
      final response = await http.delete(
        Uri.parse(ApiEndpoints.goalDelete(goalId)),
        headers: await _authHeaders(),
      );

      if (response.statusCode != 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(body['message'] ?? 'Failed to delete goal');
      }
    } catch (e) {
      throw Exception('Error deleting goal: $e');
    }
  }

  /// POST /api/goals/:id/contributions
  Future<Map<String, dynamic>> contribute(
    String goalId, {
    required double amount,
    String? note,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.goalContributions(goalId)),
        headers: await _authHeaders(),
        body: jsonEncode({'amount': amount, 'note': ?note}),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 201) {
        return body;
      } else {
        throw Exception(body['message'] ?? 'Failed to add contribution');
      }
    } catch (e) {
      throw Exception('Error adding contribution: $e');
    }
  }

  /// GET /api/goals/:id/contributions
  Future<List<dynamic>> fetchContributions(String goalId) async {
    try {
      final response = await http.get(
        Uri.parse(ApiEndpoints.goalContributions(goalId)),
        headers: await _authHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      } else {
        throw Exception(
          'Failed to fetch contributions (status ${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Error fetching contributions: $e');
    }
  }
}
