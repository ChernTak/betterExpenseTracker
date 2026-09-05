import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../core/constants/api_endpoints.dart';
import '../features/auth/domain/entities/user.dart';

/// Handles registration, login, password reset, and secure storage of the JWT session token.
class AuthService {
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'jwt_token';
  // Persisted so the app can route admin accounts without decoding the JWT on every screen (FR1.7).
  static const _roleKey = 'user_role';
  // Lets AdminUsersScreen hide deactivate/delete on the admin's own row specifically, not every admin row.
  static const _userIdKey = 'user_id';
  // Whether AuthGate should resume a leftover session on cold start, independent of the token itself.
  static const _rememberMeKey = 'remember_me';

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
          if (mobileNumber != null && mobileNumber.isNotEmpty)
            'mobileNumber': mobileNumber,
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

  /// POST /api/auth/login — saves the JWT to secure storage; [rememberMe] only controls resume-on-cold-start, not this run's validity.
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    bool rememberMe = false,
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
        await setRememberMe(rememberMe);
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
        // A guest account is throwaway by design — never resume it across
        // an app restart, regardless of any earlier Remember Me choice.
        await setRememberMe(false);
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
    if (token == null)
      return; // not logged in yet, nothing to attach the token to

    try {
      final response = await http.put(
        Uri.parse(ApiEndpoints.authFcmToken()),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'fcmToken': fcmToken}),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to register FCM token (status ${response.statusCode})',
        );
      }
    } catch (e) {
      throw Exception('Error registering FCM token: $e');
    }
  }

  /// PUT /api/auth/location-consent — explicit opt-in for the GPS-based food
  /// recommendation feature. Called right before the first location read.
  Future<void> updateLocationConsent(bool consent) async {
    final token = await getToken();
    if (token == null) return;

    try {
      final response = await http.put(
        Uri.parse(ApiEndpoints.authLocationConsent()),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'locationConsent': consent}),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to update location consent (status ${response.statusCode})',
        );
      }
    } catch (e) {
      throw Exception('Error updating location consent: $e');
    }
  }

  /// PUT /api/auth/background-location-consent — separate opt-in from updateLocationConsent since always-on tracking is a bigger privacy ask.
  Future<void> updateBackgroundLocationConsent(bool consent) async {
    final token = await getToken();
    if (token == null) return;

    try {
      final response = await http.put(
        Uri.parse(ApiEndpoints.authBackgroundLocationConsent()),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'backgroundLocationConsent': consent}),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to update background location consent (status ${response.statusCode})',
        );
      }
    } catch (e) {
      throw Exception('Error updating background location consent: $e');
    }
  }

  /// GET /api/auth/me — for the Settings screen.
  Future<User> fetchProfile() async {
    final token = await getToken();
    if (token == null) throw Exception('Not logged in');

    try {
      final response = await http.get(
        Uri.parse(ApiEndpoints.authMe()),
        headers: {'Authorization': 'Bearer $token'},
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return User.fromJson(body);
      } else {
        throw Exception(body['message'] ?? 'Failed to fetch profile');
      }
    } catch (e) {
      throw Exception('Error fetching profile: $e');
    }
  }

  Future<String?> getToken() => _storage.read(key: _tokenKey);

  Future<bool> isLoggedIn() async => (await getToken()) != null;

  Future<String?> getRole() => _storage.read(key: _roleKey);

  Future<bool> isAdmin() async => (await getRole()) == 'admin';

  Future<String?> getUserId() => _storage.read(key: _userIdKey);

  Future<void> setRememberMe(bool value) =>
      _storage.write(key: _rememberMeKey, value: value.toString());

  Future<bool> getRememberMe() async =>
      (await _storage.read(key: _rememberMeKey)) == 'true';

  /// Called once at startup by AuthGate to decide whether to resume a leftover session or wipe it; a missing (pre-upgrade) key is treated as legacy, not opt-out, so only an explicit 'false' wipes it.
  Future<bool> hasValidSession() async {
    final storedRememberMe = await _storage.read(key: _rememberMeKey);
    if (storedRememberMe == 'false') {
      await logout();
      return false;
    }
    return isLoggedIn();
  }

  Future<void> logout() => _storage.deleteAll();
}
