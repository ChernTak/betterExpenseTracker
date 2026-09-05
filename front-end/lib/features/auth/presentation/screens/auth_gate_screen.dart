import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../route.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/fcm_service.dart';

/// Startup landing spot: resolves Remember Me via AuthService.hasValidSession(), then redirects to login/admin/main.
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
      // Secure storage read failed (e.g. keystore invalidated by an OS update) — fall back to login instead of stalling here.
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
