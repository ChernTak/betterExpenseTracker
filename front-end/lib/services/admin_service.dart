import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/constants/api_endpoints.dart';
import 'auth_service.dart';

/// A row from GET /api/admin/users. password_hash is never returned by the
/// backend (see back-end/src/models/user.model.js findAllForAdmin).
class AdminUser {
  final String userId;
  final String email;
  final String username;
  final String role;
  final bool isGuest;
  final bool isActive;
  final bool isLocked;
  final DateTime? deactivatedAt;
  final DateTime createdAt;

  const AdminUser({
    required this.userId,
    required this.email,
    required this.username,
    required this.role,
    required this.isGuest,
    required this.isActive,
    required this.isLocked,
    required this.deactivatedAt,
    required this.createdAt,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      userId: json['user_id'] as String,
      email: json['email'] as String,
      username: json['username'] as String,
      role: json['role'] as String,
      isGuest: json['is_guest'] as bool,
      isActive: json['is_active'] as bool,
      isLocked: json['is_locked'] as bool,
      deactivatedAt: json['deactivated_at'] != null ? DateTime.parse(json['deactivated_at'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Service layer for FR1.7 (admin account management: view/deactivate/delete).
/// Every call requires a JWT for an account with role='admin' — the backend
/// enforces this via admin.middleware.js regardless of what the client sends.
class AdminService {
  final _authService = AuthService();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _authService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/admin/users
  Future<List<AdminUser>> fetchUsers() async {
    try {
      final response = await http.get(Uri.parse(ApiEndpoints.adminUsers()), headers: await _authHeaders());
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return (body['users'] as List<dynamic>)
            .map((e) => AdminUser.fromJson(e as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception(body['message'] ?? 'Failed to load users');
      }
    } catch (e) {
      throw Exception('Error loading users: $e');
    }
  }

  /// PATCH /api/admin/users/:id/deactivate
  Future<void> deactivateUser(String userId) => _patch(ApiEndpoints.adminDeactivateUser(userId));

  /// PATCH /api/admin/users/:id/reactivate
  Future<void> reactivateUser(String userId) => _patch(ApiEndpoints.adminReactivateUser(userId));

  Future<void> _patch(String url) async {
    final response = await http.patch(Uri.parse(url), headers: await _authHeaders());
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? 'Request failed (status ${response.statusCode})');
    }
  }

  /// DELETE /api/admin/users/:id — permanent (PDPA data-deletion, FR1.7).
  Future<void> deleteUser(String userId) async {
    final response = await http.delete(Uri.parse(ApiEndpoints.adminDeleteUser(userId)), headers: await _authHeaders());
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? 'Failed to delete user (status ${response.statusCode})');
    }
  }
}
