import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// Registers this device's FCM token with the backend (FR3.5) for budget alerts; call `registerToken()` once after login.
class FcmService {
  final _messaging = FirebaseMessaging.instance;
  final _authService = AuthService();

  Future<void> registerToken() async {
    try {
      await _messaging.requestPermission();

      final token = await _messaging.getToken();
      if (token != null) {
        if (kDebugMode) debugPrint('FCM token: $token');
        await _authService.updateFcmToken(token);
      }

      // FCM can rotate the token later — keep the backend in sync
      _messaging.onTokenRefresh.listen((newToken) {
        _authService.updateFcmToken(newToken);
      });
    } catch (e) {
      // Notification permission denied or plugin unavailable shouldn't block
      // login — budget alerts just fall back to the in-app "Recent Alerts" list.
    }
  }
}
