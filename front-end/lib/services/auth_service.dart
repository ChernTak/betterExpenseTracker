import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../core/constants/api_endpoints.dart';

/// Service layer for the Auth feature.
///
/// Handles registration, login and password reset calls to the backend,
/// plus secure on-device storage of the JWT session token. Screens should
/// call these methods rather than building HTTP requests themselves.
class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'jwt_token';
  // FR1.7 — the JWT already carries `role` (see back-end auth.service.js),
  // but nothing previously read it client-side. Persisting it lets the app
  // route admin accounts to the admin screen instead of the expense-tracking
  // shell, without decoding the token on every screen that needs to know.
  static const _roleKey = 'user_role';
  // FR1.7 — AdminUsersScreen needs to know which row in the user list is
  // "me" so it can hide the deactivate/delete actions on the admin's own
  // account (comparing by role alone was wrong: it hid the buttons on
  // every admin row, not just the logged-in admin's own).
  static const _userIdKey = 'user_id';

  // Shared by login() and continueAsGuest() — both return the same
  // { token, user: { userId, role, ... } } shape on success.
  Future<void> _persistSession(Map<String, dynamic> body) async {
    await _storage.write(key: _tokenKey, value: body['token'] as String);
    final user = body['user'] as Map<String, dynamic>?;
    final role = user?['role'] as String?;
    final userId = user?['userId'] as String?;
    if (role != null) await _storage.write(key: _roleKey, value: role);
    if (userId != null) await _storage.write(key: _userIdKey, value: userId);
  }

  /// POST /api/auth/register
  Future<Map<String, dynamic>> register({
    required String email,
    required String username,
    required String password,
    String? mobileNumber,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.authRegister()),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'username': username,
          'password': password,
          if (mobileNumber != null && mobileNumber.isNotEmpty) 'mobileNumber': mobileNumber,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 201) {
        return body;
      } else {
        throw Exception(body['message'] ?? 'Registration failed');
      }
    } catch (e) {
      throw Exception('Error registering: $e');
    }
  }

  /// POST /api/auth/login — saves the JWT token to secure storage on success.
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.authLogin()),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        await _persistSession(body);
        return body;
      } else {
        // Surfaces backend messages like account-locked (423) distinctly,
        // and deactivated (403, see FR1.7 — admin.service.js deactivateUser)
        throw Exception(body['message'] ?? 'Login failed');
      }
    } catch (e) {
      throw Exception('Error logging in: $e');
    }
  }

  /// POST /api/auth/guest — creates a throwaway account and logs straight
  /// into it, skipping the registration form entirely.
  Future<Map<String, dynamic>> continueAsGuest() async {
    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.authGuest()),
        headers: {'Content-Type': 'application/json'},
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        await _persistSession(body);
        return body;
      } else {
        throw Exception(body['message'] ?? 'Failed to continue as guest');
      }
    } catch (e) {
      throw Exception('Error continuing as guest: $e');
    }
  }

  /// POST /api/auth/reset-password — request a reset link be emailed.
  Future<String> requestPasswordReset(String email) async {
    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.authRequestPasswordReset()),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return body['message'] as String;
      } else {
        throw Exception(body['message'] ?? 'Failed to request password reset');
      }
    } catch (e) {
      throw Exception('Error requesting password reset: $e');
    }
  }

  /// POST /api/auth/reset-password/confirm — submit the token + new password.
  Future<String> confirmPasswordReset({
    required String token,
    required String newPassword,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.authConfirmPasswordReset()),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token, 'newPassword': newPassword}),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return body['message'] as String;
      } else {
        throw Exception(body['message'] ?? 'Failed to reset password');
      }
    } catch (e) {
      throw Exception('Error confirming password reset: $e');
    }
  }

  /// PUT /api/auth/fcm-token — registers this device's FCM token so budget
  /// alerts (FR3.5) have somewhere to push to. Called by FcmService after login.
  Future<void> updateFcmToken(String fcmToken) async {
    final token = await getToken();
    if (token == null) return; // not logged in yet, nothing to attach the token to

    try {
      final response = await http.put(
        Uri.parse(ApiEndpoints.authFcmToken()),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
        body: jsonEncode({'fcmToken': fcmToken}),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to register FCM token (status ${response.statusCode})');
      }
    } catch (e) {
      throw Exception('Error registering FCM token: $e');
    }
  }

  Future<String?> getToken() => _storage.read(key: _tokenKey);

  Future<bool> isLoggedIn() async => (await getToken()) != null;

  Future<String?> getRole() => _storage.read(key: _roleKey);

  Future<bool> isAdmin() async => (await getRole()) == 'admin';

  Future<String?> getUserId() => _storage.read(key: _userIdKey);

  Future<void> logout() => _storage.deleteAll();
}
