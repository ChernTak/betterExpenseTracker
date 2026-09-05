import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../wishlist/presentation/screens/wishlist_screen.dart';

/// Routes incoming FCM `budget_alert`/`location_nudge` messages across foreground (SnackBar), background (`onMessageOpenedApp`), and terminated (`getInitialMessage`) states; both types are "wishlist triggers" whose alertId a created wishlist item attaches to.
class NotificationHandler {
  static void init() {
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _handleNotificationTap(message);
    });
  }

  static bool _isWishlistTrigger(Map<String, dynamic> data) {
    final type = data['type'];
    return (type == 'budget_alert' || type == 'location_nudge') &&
        data['alertId'] != null;
  }

  // A terminated-state tap can resolve before any screen exists, so it waits here until MainShell.initState calls back in.
  static Map<String, dynamic>? _pendingTapData;

  static void _handleNotificationTap(RemoteMessage message) {
    if (!_isWishlistTrigger(message.data)) return;
    _pendingTapData = message.data;
    tryShowPendingWishlistDialog();
  }

  /// Shows the pending tap's dialog if a navigable context exists, otherwise leaves it pending; safe to call speculatively.
  static void tryShowPendingWishlistDialog() {
    final data = _pendingTapData;
    final context = MyApp.navigatorKey.currentContext;
    if (data == null || context == null) return;
    _pendingTapData = null;

    showDialog<bool>(
      context: context,
      builder: (_) => AddToWishlistDialog(
        alertId: data['alertId'] as String?,
        initialCategory: data['category'] as String?,
      ),
    );
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    if (_isWishlistTrigger(message.data) ||
        message.data['type'] == 'budget_alert') {
      _showAlertSnackBar(message);
    }
  }

  static void _showAlertSnackBar(RemoteMessage message) {
    final body = message.notification?.body ?? 'Alert';
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
        action: _isWishlistTrigger(message.data)
            ? SnackBarAction(
                label: 'Delay it',
                textColor: Colors.white,
                onPressed: () {
                  _pendingTapData = message.data;
                  tryShowPendingWishlistDialog();
                },
              )
            : null,
      ),
    );
  }
}
