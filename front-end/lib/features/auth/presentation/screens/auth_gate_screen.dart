import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../route.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/fcm_service.dart';

/// App startup landing spot. Resolves the Remember Me state before the user
/// sees anything: a spinner while `AuthService.hasValidSession()` reads
/// secure storage, then a redirect straight to the login screen, the admin
/// screen, or the expense-tracking shell — whichever a checked "Remember me"
/// on a previous login earns them.
class AuthGateScreen extends StatefulWidget {
  const AuthGateScreen({super.key});

  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> {
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _resolveStartRoute();
  }

  Future<void> _resolveStartRoute() async {
    try {
      final hasSession = await _authService.hasValidSession();
      if (!hasSession) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, AppRoutes.login);
        return;
      }

      unawaited(FcmService().registerToken());

      final role = await _authService.getRole();
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        role == 'admin' ? AppRoutes.admin : AppRoutes.main,
      );
    } catch (_) {
      // Secure storage read failed (e.g. Android keystore invalidated after
      // an OS update or app restore) — fall back to the login screen rather
      // than leaving the user stuck on this spinner forever.
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
