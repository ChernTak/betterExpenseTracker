import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/food_recommendation_service.dart';
import '../../../expense/presentation/screens/log_venue_expense_screen.dart';
import '../widgets/venue_photo.dart';

/// Pill for "Halal" / "Visited Nx before" callouts, matching _VenueCard's badge style but built inline as a plain function here.
Widget _venueBadge({required IconData icon, required String text}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.primaryMuted,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.primary),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12)),
      ],
    ),
  );
}

/// Shows the list's summary instantly, then fetches address/phone/website/hours in the background (cached server-side); no ratings/photos (Foursquare Premium, out of scope) and hours is shown as a raw string with no "open now" parsing.
class VenueDetailScreen extends StatefulWidget {
  final Map<String, dynamic> venue;

  const VenueDetailScreen({super.key, required this.venue});

  @override
  State<VenueDetailScreen> createState() => _VenueDetailScreenState();
}

class _VenueDetailScreenState extends State<VenueDetailScreen> {
  final _recommendationService = FoodRecommendationService();
  final _authService = AuthService();

  Map<String, dynamic>? _detail;
  String? _errorMessage;
  Map<String, String>? _imageHeaders;

  @override
  void initState() {
    super.initState();
    _loadDetail();
    _loadImageHeaders();
  }

  Future<void> _loadImageHeaders() async {
    final token = await _authService.getToken();
    if (!mounted) return;
    setState(() => _imageHeaders = token != null ? {'Authorization': 'Bearer $token'} : null);
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

  void _logExpense() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LogVenueExpenseScreen(
          initialMerchantName: widget.venue['name'] as String?,
          initialCategory: 'food_dining',
        ),
      ),
    );
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
          VenuePhoto(
            photoPath: widget.venue['photoUrl'] as String?,
            authHeaders: _imageHeaders,
            width: double.infinity,
            height: 180,
            borderRadius: BorderRadius.circular(16),
          ),
          const SizedBox(height: 16),
          if (categories.isNotEmpty || distanceLabel != null)
            Text(
              [if (categories.isNotEmpty) categories.first, ?distanceLabel].join(' • '),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          if (widget.venue['previouslyVisited'] == true ||
              (widget.venue['dietary'] as Map<String, dynamic>?)?['halal'] == true) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if ((widget.venue['dietary'] as Map<String, dynamic>?)?['halal'] == true)
                  _venueBadge(icon: Icons.check_circle_outline, text: 'Halal'),
                if (widget.venue['previouslyVisited'] == true)
                  _venueBadge(
                    icon: Icons.history,
                    text: 'Visited ${(widget.venue['visitCount'] as num?)?.toInt() ?? 0}x before',
                  ),
              ],
            ),
          ],
          // Always available immediately — doesn't need to wait on the
          // detail fetch since lat/lng/name are already known from the list.
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _logExpense,
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('Log Expense'),
                ),
              ),
              if (hasCoords) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openDirections,
                    icon: const Icon(Icons.directions_outlined, size: 18),
                    label: const Text('Directions'),
                  ),
                ),
              ],
            ],
          ),
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
