import 'package:flutter/material.dart';

/// Design tokens shared across every screen so the app reads as one
/// consistent visual system (deep forest green + soft neutral surfaces).
class AppColors {
  static const primary = Color(0xFF12463A); // deep forest green — CTAs, links, selected nav, positive amounts
  static const primaryMuted = Color(0xFFE1EEE8); // pale mint — tip/insight card backgrounds
  static const surface = Color(0xFFF1F2F4); // light gray — input fields, segmented tracks, unselected chips
  static const textPrimary = Color(0xFF1A1A1A);
  static const textSecondary = Color(0xFF8B8F97);
  static const expense = Color(0xFFD64545); // red — expense amounts, critical alerts

  // Kept for the few call sites that still key alert severity off a warm tone.
  static const warning = Color(0xFFB8860B);
}
