import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/constants/api_endpoints.dart';
import 'auth_service.dart';

/// Service layer for Wishlist — a single tempting purchase deliberately
/// delayed. Meant to be created from a real-time behavioral alert (see
/// budget_alert/location_nudge handling in notification_handler.dart), not
/// from a standalone "add item" flow, though [addItem] doesn't require an
/// alertId so a manual add still works.
class WishlistService {
  final _authService = AuthService();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _authService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// POST /api/wishlist
  Future<Map<String, dynamic>> addItem({
    String? alertId,
    required String itemName,
    double? estimatedCost,
    String? merchantName,
    String? category,
    int? delayDays,
    String? notes,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.wishlist),
        headers: await _authHeaders(),
        body: jsonEncode({
          'alertId': ?alertId,
          'itemName': itemName,
          'estimatedCost': ?estimatedCost,
          'merchantName': ?merchantName,
          'category': ?category,
          'delayDays': ?delayDays,
          'notes': ?notes,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 201) {
        return body;
      } else {
        throw Exception(body['message'] ?? 'Failed to add wishlist item');
      }
    } catch (e) {
      throw Exception('Error adding wishlist item: $e');
    }
  }

  /// GET /api/wishlist?status=... — omit [status] for every item.
  Future<List<dynamic>> fetchItems({String? status}) async {
    try {
      final response = await http.get(
        Uri.parse(ApiEndpoints.wishlistList(status: status)),
        headers: await _authHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      } else {
        throw Exception(
          'Failed to fetch wishlist (status ${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Error fetching wishlist: $e');
    }
  }

  /// PUT /api/wishlist/:id — also how an item resolves (status: purchased/dismissed).
  Future<Map<String, dynamic>> updateItem(
    String wishlistId, {
    String? itemName,
    double? estimatedCost,
    String? merchantName,
    String? category,
    String? status,
    String? notes,
  }) async {
    try {
      final response = await http.put(
        Uri.parse(ApiEndpoints.wishlistUpdate(wishlistId)),
        headers: await _authHeaders(),
        body: jsonEncode({
          'itemName': ?itemName,
          'estimatedCost': ?estimatedCost,
          'merchantName': ?merchantName,
          'category': ?category,
          'status': ?status,
          'notes': ?notes,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return body;
      } else {
        throw Exception(body['message'] ?? 'Failed to update wishlist item');
      }
    } catch (e) {
      throw Exception('Error updating wishlist item: $e');
    }
  }

  /// POST /api/wishlist/:id/convert-to-goal — resolves a pending item by
  /// starting a funded goal for it instead of buying now or dismissing it.
  /// [targetAmount] only needs to be passed if the item has no
  /// estimated_cost or the user wants to save toward a different figure.
  Future<Map<String, dynamic>> convertToGoal(
    String wishlistId, {
    double? targetAmount,
    DateTime? deadlineDate,
    int? priority,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.wishlistConvertToGoal(wishlistId)),
        headers: await _authHeaders(),
        body: jsonEncode({
          'targetAmount': ?targetAmount,
          if (deadlineDate != null)
            'deadlineDate': deadlineDate.toIso8601String().substring(0, 10),
          'priority': ?priority,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 201) {
        return body;
      } else {
        throw Exception(body['message'] ?? 'Failed to convert to goal');
      }
    } catch (e) {
      throw Exception('Error converting wishlist item to goal: $e');
    }
  }

  /// DELETE /api/wishlist/:id
  Future<void> deleteItem(String wishlistId) async {
    try {
      final response = await http.delete(
        Uri.parse(ApiEndpoints.wishlistDelete(wishlistId)),
        headers: await _authHeaders(),
      );

      if (response.statusCode != 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(body['message'] ?? 'Failed to delete wishlist item');
      }
    } catch (e) {
      throw Exception('Error deleting wishlist item: $e');
    }
  }
}
