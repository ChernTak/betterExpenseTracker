import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/constants/api_endpoints.dart';
import 'auth_service.dart';

/// Every network call to the `/api/expenses` backend routes lives here, not inside UI widgets.
class ExpenseService {
  final _authService = AuthService();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _authService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/expenses/fetch — returns the logged-in user's expenses.
  Future<List<dynamic>> fetchAllExpenses() async {
    try {
      final response = await http.get(
        Uri.parse(ApiEndpoints.expenseFetchAll()),
        headers: await _authHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      } else {
        throw Exception(
          'Failed to fetch expenses (status ${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Error fetching expenses: $e');
    }
  }

  /// GET /api/expenses/:id — returns a single expense, or throws if not found.
  Future<Map<String, dynamic>> fetchExpenseById(String id) async {
    try {
      final response = await http.get(
        Uri.parse(ApiEndpoints.expenseById(id)),
        headers: await _authHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 404) {
        throw Exception('Expense not found');
      } else {
        throw Exception(
          'Failed to fetch expense (status ${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Error fetching expense: $e');
    }
  }

  /// POST /api/expenses/post — creates a new expense record for the logged-in user.
  Future<Map<String, dynamic>> createExpense(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.expenseCreate()),
        headers: await _authHeaders(),
        body: jsonEncode(data),
      );

      if (response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception(
          'Failed to create expense (status ${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Error creating expense: $e');
    }
  }

  /// PUT /api/expenses/update/:id — updates an existing expense record.
  Future<Map<String, dynamic>> updateExpense(
    String id,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await http.put(
        Uri.parse(ApiEndpoints.expenseUpdate(id)),
        headers: await _authHeaders(),
        body: jsonEncode(data),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else if (response.statusCode == 404) {
        throw Exception('Expense not found');
      } else {
        throw Exception(
          'Failed to update expense (status ${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Error updating expense: $e');
    }
  }

  /// DELETE /api/expenses/delete/:id — removes an expense record.
  Future<void> deleteExpense(String id) async {
    try {
      final response = await http.delete(
        Uri.parse(ApiEndpoints.expenseDelete(id)),
        headers: await _authHeaders(),
      );

      if (response.statusCode == 200) {
        return;
      } else if (response.statusCode == 404) {
        throw Exception('Expense not found');
      } else {
        throw Exception(
          'Failed to delete expense (status ${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Error deleting expense: $e');
    }
  }
}
