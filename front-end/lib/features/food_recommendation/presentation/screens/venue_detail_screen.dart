import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../services/food_recommendation_service.dart';

/// Venue detail screen. Takes the summary already known from the list
/// (name/distance/price/category/lat/lng) for an instant first paint, then
/// fetches address/phone/website/hours in the background — served from the
/// backend's venue_cache when available, so repeat opens of a popular venue
/// are fast and don't re-bill the provider that sourced it. No
/// ratings/photos: those are Foursquare Premium fields, out of scope for
/// now (see plan). Hours is a raw OSM-style string, shown as-is — no
/// "open now" parsing (that syntax has real edge cases not worth the risk
/// for a first pass).
class VenueDetailScreen extends StatefulWidget {
  final Map<String, dynamic> venue;

  const VenueDetailScreen({super.key, required this.venue});

  @override
  State<VenueDetailScreen> createState() => _VenueDetailScreenState();
}

class _VenueDetailScreenState extends State<VenueDetailScreen> {
  final _recommendationService = FoodRecommendationService();

  Map<String, dynamic>? _detail;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() => _errorMessage = null);
    try {
      final detail = await _recommendationService.fetchVenueDetail(
        widget.venue['provider'] as String,
        widget.venue['id'] as String,
      );
      if (!mounted) return;
      setState(() => _detail = detail);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    }
  }

  bool get _hasAnyDetail =>
      ((_detail?['address'] as String?)?.isNotEmpty ?? false) ||
      ((_detail?['tel'] as String?)?.isNotEmpty ?? false) ||
      ((_detail?['website'] as String?)?.isNotEmpty ?? false) ||
      ((_detail?['hours'] as String?)?.isNotEmpty ?? false);

  Future<void> _openDirections() async {
    final lat = (widget.venue['lat'] as num?)?.toDouble();
    final lng = (widget.venue['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _callPhone(String tel) async {
    await launchUrl(Uri(scheme: 'tel', path: tel));
  }

  Future<void> _openWebsite(String website) async {
    final hasScheme = website.startsWith('http://') || website.startsWith('https://');
    final uri = Uri.parse(hasScheme ? website : 'https://$website');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.venue['name'] as String? ?? 'Unknown venue';
    final categories = (widget.venue['categories'] as List<dynamic>? ?? []).cast<String>();
    final distanceM = (widget.venue['distanceM'] as num?)?.toDouble();
    final distanceLabel = distanceM == null
        ? null
        : distanceM < 1000
            ? '${distanceM.round()}m away'
            : '${(distanceM / 1000).toStringAsFixed(1)}km away';
    final loading = _detail == null && _errorMessage == null;
    final hasCoords = widget.venue['lat'] != null && widget.venue['lng'] != null;
    final tel = _detail?['tel'] as String?;
    final website = _detail?['website'] as String?;

    return Scaffold(
      appBar: AppBar(title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (categories.isNotEmpty || distanceLabel != null)
            Text(
              [if (categories.isNotEmpty) categories.first, ?distanceLabel].join(' • '),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          // Always available immediately — doesn't need to wait on the
          // detail fetch since lat/lng are already known from the list.
          if (hasCoords) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openDirections,
              icon: const Icon(Icons.directions_outlined, size: 18),
              label: const Text('Get Directions'),
            ),
          ],
          const SizedBox(height: 16),
          _DetailRow(icon: Icons.location_on_outlined, label: 'Address', value: _detail?['address'] as String?, loading: loading),
          _DetailRow(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: tel,
            loading: loading,
            onTap: (tel != null && tel.isNotEmpty) ? () => _callPhone(tel) : null,
          ),
          _DetailRow(
            icon: Icons.public,
            label: 'Website',
            value: website,
            loading: loading,
            onTap: (website != null && website.isNotEmpty) ? () => _openWebsite(website) : null,
          ),
          _DetailRow(icon: Icons.access_time, label: 'Hours', value: _detail?['hours'] as String?, loading: loading),
          if (!loading && _errorMessage == null && !_hasAnyDetail)
            Text(
              'No additional details available for this venue.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(_errorMessage!, style: const TextStyle(color: AppColors.expense, fontSize: 13)),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _loadDetail, child: const Text('Retry')),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final bool loading;
  final VoidCallback? onTap;

  const _DetailRow({required this.icon, required this.label, required this.value, required this.loading, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (!loading && (value == null || value!.isEmpty)) return const SizedBox.shrink();

    final content = Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 2),
                if (loading)
                  const SizedBox(
                    height: 14,
                    width: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Text(
                    value!,
                    style: TextStyle(fontSize: 15, color: onTap != null ? AppColors.primary : null),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: content);
  }
}
