import 'package:flutter/material.dart';

import '../../../../core/constants/api_endpoints.dart';
import '../../../../core/constants/app_colors.dart';

/// Renders a venue's Google Places photo (proxied through our own backend —
/// see recommendation.service.js#getVenuePhoto — so the Google API key
/// never reaches the client), falling back to a plain category-style icon
/// when there's no photo or the request fails. `authHeaders` is passed in
/// rather than fetched here so a list of these doesn't each hit secure
/// storage separately — the parent screen fetches it once.
class VenuePhoto extends StatelessWidget {
  final String? photoPath;
  final Map<String, String>? authHeaders;
  // `size` is the shorthand for a square thumbnail (venue cards); pass
  // `width`/`height` separately instead for a rectangular banner (venue
  // detail screen) — either way the fallback icon scales off whichever is
  // smaller, so it never overflows a short-but-wide banner.
  final double size;
  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  const VenuePhoto({
    super.key,
    required this.photoPath,
    required this.authHeaders,
    this.size = 56,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  double get _width => width ?? size;
  double get _height => height ?? size;

  @override
  Widget build(BuildContext context) {
    if (photoPath == null) return _fallback();

    return ClipRRect(
      borderRadius: borderRadius,
      child: Image.network(
        ApiEndpoints.recommendationVenuePhoto(photoPath!),
        width: _width,
        height: _height,
        fit: BoxFit.cover,
        headers: authHeaders,
        loadingBuilder: (context, child, progress) => progress == null ? child : _placeholder(),
        errorBuilder: (context, error, stack) => _fallback(),
      ),
    );
  }

  Widget _fallback() {
    final iconSize = (_width < _height ? _width : _height) * 0.5;
    return Container(
      width: _width,
      height: _height,
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: borderRadius),
      child: Icon(Icons.restaurant_outlined, color: AppColors.textSecondary, size: iconSize),
    );
  }

  Widget _placeholder() {
    final indicatorSize = (_width < _height ? _width : _height) * 0.35;
    return Container(
      width: _width,
      height: _height,
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: borderRadius),
      child: Center(
        child: SizedBox(
          width: indicatorSize,
          height: indicatorSize,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
