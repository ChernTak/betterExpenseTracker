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
        await _storage.write(key: _tokenKey, value: body['token'] as String);
        return body;
      } else {
        // Surfaces backend messages like account-locked (423) distinctly
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
        await _storage.write(key: _tokenKey, value: body['token'] as String);
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

  Future<void> logout() => _storage.delete(key: _tokenKey);
}
