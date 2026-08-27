import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../wishlist/presentation/screens/wishlist_screen.dart';

/// Routes incoming FCM messages, in all three delivery states (FR3.5 +
/// the location-nudge feature).
///
/// Sent by back-end/src/services/budget.service.js / nudge.service.js with a
/// `notification` payload (title/body) and a `data` payload:
/// `{ type: 'budget_alert', category, alertType, budgetId, alertId }` or
/// `{ type: 'location_nudge', venueId, budgetId, alertId }`. Both types are
/// "wishlist triggers" — alertId is the FK a created wishlist item attaches
/// to (see wishlist.model.js/AddToWishlistDialog).
///
/// - Foreground: shown as a SnackBar with a "Delay it" action.
/// - Background (app alive, tapped from the system tray): `onMessageOpenedApp`.
/// - Terminated (app launched by the tap): `getInitialMessage()` at startup.
/// Background/terminated messages are otherwise displayed automatically by
/// the OS using the `notification` payload — no extra code needed for that.
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

  // Set on tap (background or terminated) and consumed by
  // tryShowPendingWishlistDialog — a terminated-state tap can resolve
  // before any screen exists to show a dialog on top of, so it waits here
  // until MainShell.initState calls back in once the user is past login.
  static Map<String, dynamic>? _pendingTapData;

  static void _handleNotificationTap(RemoteMessage message) {
    if (!_isWishlistTrigger(message.data)) return;
    _pendingTapData = message.data;
    tryShowPendingWishlistDialog();
  }

  /// Shows the dialog for a pending tap if one is stored and a navigable
  /// context is currently available; otherwise leaves it pending. Safe to
  /// call speculatively (e.g. every time MainShell mounts).
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
