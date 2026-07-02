import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../../app.dart';

/// Routes incoming FCM messages while the app is open (FR3.5).
///
/// Budget alerts are sent by back-end/src/utils/pushNotifier.js with a
/// `notification` payload (title/body) and a `data` payload:
/// `{ type: 'budget_alert', category, alertType, budgetId }`. Background/
/// terminated-state messages are shown automatically by the OS using the
/// `notification` payload — no extra code needed for that case.
class NotificationHandler {
  static void init() {
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    if (message.data['type'] == 'budget_alert') {
      _showBudgetAlert(message);
    }
  }

  static void _showBudgetAlert(RemoteMessage message) {
    final body = message.notification?.body ?? 'Budget alert';
    final color = switch (message.data['alertType']) {
      'critical_alert' => Colors.red,
      'budget_warning' => Colors.deepOrange,
      _ => Colors.amber.shade800,
    };

    MyApp.scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(body),
        backgroundColor: color,
        duration: const Duration(seconds: 6),
      ),
    );
  }
}
