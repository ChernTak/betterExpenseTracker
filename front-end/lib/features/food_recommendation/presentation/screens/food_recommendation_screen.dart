import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/food_recommendation_service.dart';
import '../../../../services/gps_service.dart';
import '../widgets/venue_photo.dart';
import 'venue_detail_screen.dart';

/// Food tab — real-time, budget-aware nearby food suggestions (Constraint-
/// Driven Utility Filtering: C_meal from the remaining food_dining budget,
/// hard radius/price filters, soft distance+price+preference ranking, all
/// computed server-side). This screen only handles location capture,
/// loading/error/empty states and rendering the ranked list.
class FoodRecommendationScreen extends StatefulWidget {
  const FoodRecommendationScreen({super.key});

  @override
  State<FoodRecommendationScreen> createState() => _FoodRecommendationScreenState();
}

enum _LoadState { loading, locationDenied, error, loaded }

class _FoodRecommendationScreenState extends State<FoodRecommendationScreen> {
  final _authService = AuthService();
  final _gpsService = GpsService();
  final _recommendationService = FoodRecommendationService();

  _LoadState _state = _LoadState.loading;
  String? _errorMessage;
  Map<String, dynamic>? _data;
  Map<String, String>? _imageHeaders;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);

    // Best-effort — consent is re-sent on every load rather than cached
    // locally, since it's a one-line PUT and keeps the backend's record
    // authoritative without adding a settings screen for this alone.
    try {
      await _authService.updateLocationConsent(true);
    } catch (_) {}

    final position = await _gpsService.getCurrentPosition();
    if (position == null) {
      if (!mounted) return;
      setState(() => _state = _LoadState.locationDenied);
      return;
    }

    try {
      final data = await _recommendationService.fetchRecommendations(
        lat: position.latitude,
        lng: position.longitude,
      );
      // Fetched once per load rather than per-card so 20 venue photos don't
      // each hit secure storage separately.
      final token = await _authService.getToken();
      if (!mounted) return;
      setState(() {
        _data = data;
        _imageHeaders = token != null ? {'Authorization': 'Bearer $token'} : null;
        _state = _LoadState.loaded;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _state = _LoadState.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: switch (_state) {
        _LoadState.loading => const _CenteredMessage(
            icon: Icons.restaurant_outlined,
            child: CircularProgressIndicator(),
          ),
        _LoadState.locationDenied => _CenteredMessage(
            icon: Icons.location_off_outlined,
            title: 'Location access needed',
            message: 'Enable location permission to see nearby food options within your budget.',
            actionLabel: 'Try again',
            onAction: _load,
          ),
        _LoadState.error => _CenteredMessage(
            icon: Icons.error_outline,
            title: 'Something went wrong',
            message: _errorMessage ?? 'Failed to load recommendations.',
            actionLabel: 'Retry',
            onAction: _load,
          ),
        _LoadState.loaded => _buildLoaded(),
      },
    );
  }

  Widget _buildLoaded() {
    final data = _data!;
    final hasBudget = data['hasBudget'] as bool? ?? false;
    final mealCap = (data['mealCap'] as num?)?.toDouble();
    final venues = (data['venues'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MealCapHeader(hasBudget: hasBudget, mealCap: mealCap),
        const SizedBox(height: 16),
        if (venues.isEmpty)
          const _CenteredMessage(
            icon: Icons.search_off,
            title: 'No nearby options found',
            message: 'Try again later or from a different spot.',
          )
        else
          ...venues.map((v) => _VenueCard(venue: v, mealCap: mealCap, imageHeaders: _imageHeaders)),
      ],
    );
  }
}

class _MealCapHeader extends StatelessWidget {
  final bool hasBudget;
  final double? mealCap;

  const _MealCapHeader({required this.hasBudget, required this.mealCap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryMuted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_outlined, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hasBudget && mealCap != null
                  ? 'Your meal budget right now: RM ${mealCap!.toStringAsFixed(2)}'
                  : 'Set a Food Dining budget to get a personalised meal cap',
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _VenueCard extends StatelessWidget {
  final Map<String, dynamic> venue;
  final double? mealCap;
  final Map<String, String>? imageHeaders;

  const _VenueCard({required this.venue, required this.mealCap, required this.imageHeaders});

  // Mirrors config/dining.js's PRICE_TIER_MYR_BANDS — Foursquare's price is
  // a 1-4 categorical tier, not an exact bill amount, so this is a rough
  // MYR approximation used only for the "you save RMx" badge.
  static const _bands = {
    1: (min: 0.0, max: 15.0),
    2: (min: 15.0, max: 30.0),
    3: (min: 30.0, max: 60.0),
    4: (min: 60.0, max: double.infinity),
  };

  ({double min, double max}) get _band => _bands[(venue['priceTier'] as num?)?.toInt() ?? 1]!;

  String get _priceLabel {
    final b = _band;
    return b.max.isInfinite ? 'RM${b.min.toStringAsFixed(0)}+' : 'RM${b.min.toStringAsFixed(0)}-${b.max.toStringAsFixed(0)}';
  }

  double? get _savings {
    if (mealCap == null) return null;
    final b = _band;
    final estimate = b.max.isInfinite ? b.min : (b.min + b.max) / 2;
    final savings = mealCap! - estimate;
    return savings > 0 ? savings : null;
  }

  @override
  Widget build(BuildContext context) {
    final distanceM = (venue['distanceM'] as num?)?.toDouble();
    final distanceLabel = distanceM == null
        ? ''
        : distanceM < 1000
            ? '${distanceM.round()}m'
            : '${(distanceM / 1000).toStringAsFixed(1)}km';
    final categories = (venue['categories'] as List<dynamic>? ?? []).cast<String>();
    final savings = _savings;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surface, width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VenueDetailScreen(venue: venue))),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VenuePhoto(photoPath: venue['photoUrl'] as String?, authHeaders: imageHeaders),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            venue['name'] as String? ?? 'Unknown venue',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(_priceLabel, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [if (categories.isNotEmpty) categories.first, if (distanceLabel.isNotEmpty) distanceLabel].join(' • '),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                    if ((venue['address'] as String?)?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 2),
                      Text(
                        venue['address'] as String,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (savings != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryMuted,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Save ~RM${savings.toStringAsFixed(0)} vs. your meal cap',
                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final String? title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? child;

  const _CenteredMessage({
    required this.icon,
    this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (child != null)
                    child!
                  else
                    Icon(icon, size: 56, color: AppColors.textSecondary),
                  if (title != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      title!,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                  ],
                  if (message != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      message!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 16),
                    OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
