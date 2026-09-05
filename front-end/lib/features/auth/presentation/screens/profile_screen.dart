import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../../../core/constants/app_colors.dart';
import '../../../../features/expense/data/datasources/voice_diagnostic_log_dao.dart';
import '../../../../features/goal/presentation/screens/goals_screen.dart';
import '../../../../features/wishlist/presentation/screens/wishlist_screen.dart';
import '../../../../route.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/geofence_service.dart';
import '../../domain/entities/user.dart';

/// Settings tab: account info plus self-contained tiles so new rows can be added without restructuring.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  final _geofenceService = GeofenceService();
  late Future<User> _userFuture;
  bool _locationConsent = false;
  bool _savingLocationConsent = false;
  bool _backgroundLocationConsent = false;
  bool _savingBackgroundLocationConsent = false;

  @override
  void initState() {
    super.initState();
    _userFuture = _loadUser();
  }

  Future<User> _loadUser() async {
    final user = await _authService.fetchProfile();
    setState(() {
      _locationConsent = user.locationConsent;
      _backgroundLocationConsent = user.backgroundLocationConsent;
    });
    return user;
  }

  Future<void> _toggleLocationConsent(bool value) async {
    setState(() {
      _locationConsent = value;
      _savingLocationConsent = true;
    });
    try {
      await _authService.updateLocationConsent(value);
    } catch (e) {
      if (!mounted) return;
      setState(() => _locationConsent = !value); // revert on failure
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _savingLocationConsent = false);
    }
  }

  // Requires a separate Android background-location permission prompt before the consent flag is set, so failure here means permission denial, not just a network error.
  Future<void> _toggleBackgroundLocationConsent(bool value) async {
    setState(() => _savingBackgroundLocationConsent = true);
    try {
      if (value) {
        final granted = await _geofenceService.requestBackgroundLocationPermission();
        if (!granted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Background location permission is required for spending-area alerts.',
              ),
            ),
          );
          return;
        }
        await _authService.updateBackgroundLocationConsent(true);
        await _geofenceService.enable();
      } else {
        await _authService.updateBackgroundLocationConsent(false);
        await _geofenceService.disable();
      }
      setState(() => _backgroundLocationConsent = value);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _savingBackgroundLocationConsent = false);
    }
  }

  void _openGoals() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GoalsScreen()),
    );
  }

  void _openWishlist() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WishlistScreen()),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You can log back in anytime with your email and password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Wipe the natively-cached token before clearing secure storage, so a logged-out session can't keep authenticating a background geofence callback.
    await _geofenceService.disable();
    await _authService.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.login,
      (route) => false,
    );
  }

  // Voice pipeline has no automatic telemetry (fully on-device) — this is the only debugging signal, and limit:200 matches the DAO's own retention cap so it sees everything the device still has.
  Future<void> _showVoiceDiagnostics() async {
    final events = await VoiceDiagnosticLogDao().recentEvents(limit: 200);
    if (!mounted) return;

    if (events.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No voice logging activity recorded yet.'),
        ),
      );
      return;
    }

    final summary = _summarizeWakeAccuracy(events);
    final report = events
        .map((e) {
          final time = DateTime.fromMillisecondsSinceEpoch(
            e['created_at'] as int,
          );
          final detail = e['detail'] as String?;
          return '$time  ${e['event']}${detail != null ? ' — $detail' : ''}';
        })
        .join('\n');

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Voice diagnostic report'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (summary != null) ...[
                  Text(summary, style: const TextStyle(fontSize: 12.5)),
                  const Divider(height: 20),
                ],
                Text(
                  report,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: '${summary ?? ''}\n\n$report'));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Copied — paste it wherever you report the issue.',
                  ),
                ),
              );
            },
            child: const Text('Copy to Clipboard'),
          ),
        ],
      ),
    );
  }

  // A proxy, not a lab-measured false-positive rate — a wake that never becomes a saved expense is the closest available signal for an accidental trigger.
  String? _summarizeWakeAccuracy(List<Map<String, dynamic>> events) {
    final counts = <String, int>{};
    for (final e in events) {
      final event = e['event'] as String;
      counts[event] = (counts[event] ?? 0) + 1;
    }

    final totalWakes = counts['wake_detected'] ?? 0;
    if (totalWakes == 0) return null;

    final saved = counts['saved'] ?? 0;
    final notSaved =
        (counts['no_speech_detected'] ?? 0) +
        (counts['parse_failed'] ?? 0) +
        (counts['discarded'] ?? 0);
    final notSavedPercent = (notSaved / totalWakes * 100).round();

    return 'Wake accuracy (last $totalWakes "Ok App" detections): '
        '$saved saved, $notSaved did not result in a saved expense '
        '(~$notSavedPercent%). "Did not result in a save" includes no '
        'speech heard, an unparseable amount, and manual discards — not '
        'just false wake-word triggers, so treat this as a rough signal, '
        'not a precise false-positive rate.';
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => setState(() => _userFuture = _loadUser()),
      child: FutureBuilder<User>(
        future: _userFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Error: ${snapshot.error}'),
                ),
              ],
            );
          }

          final user = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ProfileHeader(user: user),
              const SizedBox(height: 20),
              const _SectionLabel('Preferences'),
              const SizedBox(height: 8),
              _SettingsGroup(
                children: [
                  _SettingsSwitchTile(
                    icon: Icons.location_on_outlined,
                    label: 'Location access',
                    subtitle: 'Used for nearby food recommendations',
                    value: _locationConsent,
                    enabled: !_savingLocationConsent,
                    onChanged: _toggleLocationConsent,
                  ),
                  _SettingsSwitchTile(
                    icon: Icons.storefront_outlined,
                    label: 'Background spending-area alerts',
                    subtitle:
                        'Notifies you when you enter a shopping area known for higher spending, even with the app closed',
                    value: _backgroundLocationConsent,
                    enabled: !_savingBackgroundLocationConsent,
                    onChanged: _toggleBackgroundLocationConsent,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const _SectionLabel('Planning'),
              const SizedBox(height: 8),
              _SettingsGroup(
                children: [
                  _SettingsActionTile(
                    icon: Icons.savings_outlined,
                    label: 'Savings Goals',
                    onTap: _openGoals,
                  ),
                  _SettingsActionTile(
                    icon: Icons.bookmark_border,
                    label: 'Wishlist',
                    onTap: _openWishlist,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const _SectionLabel('Support'),
              const SizedBox(height: 8),
              _SettingsGroup(
                children: [
                  _SettingsActionTile(
                    icon: Icons.mic_none,
                    label: 'Voice diagnostic report',
                    onTap: _showVoiceDiagnostics,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const _SectionLabel('Account'),
              const SizedBox(height: 8),
              _SettingsGroup(
                children: [
                  _SettingsActionTile(
                    icon: Icons.logout,
                    label: 'Log out',
                    destructive: true,
                    onTap: _logout,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

class _ProfileHeader extends StatelessWidget {
  final User user;

  const _ProfileHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    final initial = user.username.isNotEmpty
        ? user.username[0].toUpperCase()
        : '?';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surface, width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.primaryMuted,
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.username,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  user.email,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Member since ${_monthNames[user.createdAt.month - 1]} ${user.createdAt.year}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 13,
        color: AppColors.textSecondary,
      ),
    );
  }
}

/// Rounded card wrapper for a set of settings rows, with a divider between
/// each so new tiles can just be appended to `children`.
class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;

  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surface, width: 1),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SettingsActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const _SettingsActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.expense : AppColors.textPrimary;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(icon, color: AppColors.textPrimary),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: const TextStyle(fontSize: 12))
          : null,
      value: value,
      onChanged: enabled ? onChanged : null,
      activeThumbColor: AppColors.primary,
    );
  }
}
