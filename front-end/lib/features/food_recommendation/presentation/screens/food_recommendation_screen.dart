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

// Best Match keeps the server's score-based order as-is; the other two
// resort the already-fetched list client-side — no network round-trip,
// unlike cuisine/radius/halal/visitFilter which all need a fresh server
// query since they change what's affordable/ranked in the first place.
enum _SortMode { bestMatch, closest, cheapest }

class _FoodRecommendationScreenState extends State<FoodRecommendationScreen> {
  final _authService = AuthService();
  final _gpsService = GpsService();
  final _recommendationService = FoodRecommendationService();

  _LoadState _state = _LoadState.loading;
  String? _errorMessage;
  Map<String, dynamic>? _data;
  Map<String, String>? _imageHeaders;

  Set<String> _selectedCuisines = {};
  double _radiusM = 800;
  bool _halalOnly = false;
  String? _visitFilter;
  _SortMode _sortMode = _SortMode.bestMatch;

  bool get _hasActiveFilters =>
      _selectedCuisines.isNotEmpty || _radiusM != 800 || _halalOnly || _visitFilter != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_FilterResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(
        initialCuisines: _selectedCuisines,
        initialRadiusM: _radiusM,
        initialHalalOnly: _halalOnly,
        initialVisitFilter: _visitFilter,
      ),
    );
    if (result == null) return;
    setState(() {
      _selectedCuisines = result.cuisines;
      _radiusM = result.radiusM;
      _halalOnly = result.halalOnly;
      _visitFilter = result.visitFilter;
    });
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
        radius: _radiusM,
        cuisines: _selectedCuisines.isEmpty ? null : _selectedCuisines.toList(),
        halal: _halalOnly,
        visitFilter: _visitFilter,
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

    // Best Match is already the server's score order — only Closest/Cheapest
    // need a client-side resort, no re-fetch involved.
    final sortedVenues = [...venues];
    switch (_sortMode) {
      case _SortMode.bestMatch:
        break;
      case _SortMode.closest:
        sortedVenues.sort(
          (a, b) => ((a['distanceM'] as num?)?.toDouble() ?? double.infinity)
              .compareTo((b['distanceM'] as num?)?.toDouble() ?? double.infinity),
        );
      case _SortMode.cheapest:
        sortedVenues.sort(
          (a, b) => ((a['priceTier'] as num?)?.toInt() ?? 1).compareTo((b['priceTier'] as num?)?.toInt() ?? 1),
        );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MealCapHeader(hasBudget: hasBudget, mealCap: mealCap),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _openFilters,
                icon: Badge(
                  isLabelVisible: _hasActiveFilters,
                  smallSize: 8,
                  child: const Icon(Icons.tune, size: 18),
                ),
                label: const Text('Filters'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<_SortMode>(
                initialValue: _sortMode,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: const [
                  DropdownMenuItem(value: _SortMode.bestMatch, child: Text('Best Match')),
                  DropdownMenuItem(value: _SortMode.closest, child: Text('Closest')),
                  DropdownMenuItem(value: _SortMode.cheapest, child: Text('Cheapest')),
                ],
                onChanged: (mode) {
                  if (mode != null) setState(() => _sortMode = mode);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (sortedVenues.isEmpty)
          const _CenteredMessage(
            icon: Icons.search_off,
            title: 'No nearby options found',
            message: 'Try again later, from a different spot, or with fewer filters.',
          )
        else
          ...sortedVenues.map((v) => _VenueCard(venue: v, mealCap: mealCap, imageHeaders: _imageHeaders)),
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
    final previouslyVisited = venue['previouslyVisited'] as bool? ?? false;
    final visitCount = (venue['visitCount'] as num?)?.toInt() ?? 0;
    final isHalal = (venue['dietary'] as Map<String, dynamic>?)?['halal'] == true;

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
                    if (previouslyVisited || savings != null || isHalal) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (isHalal) _Badge(text: 'Halal', icon: Icons.check_circle_outline),
                          if (previouslyVisited) _Badge(text: 'Visited ${visitCount}x', icon: Icons.history),
                          if (savings != null)
                            _Badge(text: 'Save ~RM${savings.toStringAsFixed(0)} vs. your meal cap'),
                        ],
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

/// Small pill used for both the "Visited Nx" and "Save ~RMx" callouts on a
/// venue card — same visual weight, `icon` optional so the savings one
/// stays text-only like it always has.
class _Badge extends StatelessWidget {
  final String text;
  final IconData? icon;

  const _Badge({required this.text, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryMuted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: AppColors.primary),
            const SizedBox(width: 4),
          ],
          Text(text, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }
}

class _FilterResult {
  final Set<String> cuisines;
  final double radiusM;
  final bool halalOnly;
  final String? visitFilter;

  const _FilterResult({
    required this.cuisines,
    required this.radiusM,
    required this.halalOnly,
    required this.visitFilter,
  });
}

/// All five filter controls behind one sheet rather than inline above the
/// list — five controls at once (cuisine, radius, halal, visit-history,
/// sort) would recreate the "cluttered" feel already flagged as feedback.
/// Sort is the one control that lives outside this sheet (see
/// _FoodRecommendationScreenState._buildLoaded) since it's a client-side
/// resort of already-fetched data, not a new server query like these four.
class _FilterSheet extends StatefulWidget {
  final Set<String> initialCuisines;
  final double initialRadiusM;
  final bool initialHalalOnly;
  final String? initialVisitFilter;

  const _FilterSheet({
    required this.initialCuisines,
    required this.initialRadiusM,
    required this.initialHalalOnly,
    required this.initialVisitFilter,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  // Mirrors config/dining.js's FOOD_CATEGORIES.overpass — the canonical
  // cuisine vocabulary shared with the backend's substring-matched
  // prefScore, not a separately invented list.
  static const _cuisineOptions = [
    ('restaurant', 'Restaurant'),
    ('fast_food', 'Fast Food'),
    ('cafe', 'Cafe'),
    ('food_court', 'Food Court'),
    ('bar', 'Bar'),
    ('pub', 'Pub'),
  ];

  late Set<String> _cuisines;
  late double _radiusM;
  late bool _halalOnly;
  late String? _visitFilter;

  @override
  void initState() {
    super.initState();
    _cuisines = {...widget.initialCuisines};
    _radiusM = widget.initialRadiusM;
    _halalOnly = widget.initialHalalOnly;
    _visitFilter = widget.initialVisitFilter;
  }

  void _reset() {
    setState(() {
      _cuisines = {};
      _radiusM = 800;
      _halalOnly = false;
      _visitFilter = null;
    });
  }

  void _apply() {
    Navigator.pop(
      context,
      _FilterResult(cuisines: _cuisines, radiusM: _radiusM, halalOnly: _halalOnly, visitFilter: _visitFilter),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Filters', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                TextButton(onPressed: _reset, child: const Text('Reset')),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'CUISINE',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _cuisineOptions.map((opt) {
                final selected = _cuisines.contains(opt.$1);
                return FilterChip(
                  label: Text(opt.$2),
                  selected: selected,
                  onSelected: (sel) => setState(() {
                    if (sel) {
                      _cuisines.add(opt.$1);
                    } else {
                      _cuisines.remove(opt.$1);
                    }
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            const Text(
              'WALKING RADIUS',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            SegmentedButton<double>(
              segments: const [
                ButtonSegment(value: 500, label: Text('500m')),
                ButtonSegment(value: 800, label: Text('800m')),
                ButtonSegment(value: 1500, label: Text('1.5km')),
              ],
              selected: {_radiusM},
              onSelectionChanged: (sel) => setState(() => _radiusM = sel.first),
            ),
            const SizedBox(height: 20),
            const Text(
              'HISTORY',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String?>(
              segments: const [
                ButtonSegment(value: null, label: Text('All')),
                ButtonSegment(value: 'new', label: Text('New to me')),
                ButtonSegment(value: 'visited', label: Text('My regulars')),
              ],
              selected: {_visitFilter},
              onSelectionChanged: (sel) => setState(() => _visitFilter = sel.first),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Prefer halal-confirmed venues'),
              subtitle: const Text(
                'Boosts confirmed-halal venues higher. Dietary tagging is sparse, so unconfirmed venues still show.',
                style: TextStyle(fontSize: 12),
              ),
              value: _halalOnly,
              onChanged: (v) => setState(() => _halalOnly = v),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _apply, child: const Text('Apply Filters')),
            ),
          ],
        ),
      ),
    );
  }
}
