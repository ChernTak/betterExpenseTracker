import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/api_endpoints.dart';

/// Remote kill-switch check (currently just FR4.4 voice hands-free logging)
/// — lets a bad rollout be disabled server-side without an app update.
///
/// Deliberately fails open: voice logging is designed to work with zero
/// connectivity ever (that's the whole point of the offline-first NFR), so
/// this must never make the feature depend on network access. It only
/// checks in opportunistically (throttled to once/day, same cadence as
/// TierBInferenceService's OTA model check) and caches the last-known value
/// so an actual kill from the backend still reaches users within a bounded
/// time whenever they do have connectivity.
class FeatureFlagService {
  static const _voiceHandsFreeKey = 'feature_flag_voice_hands_free';
  static const _lastCheckedKey = 'feature_flag_last_checked';
  static const _checkInterval = Duration(days: 1);

  final http.Client _client;

  FeatureFlagService({http.Client? client}) : _client = client ?? http.Client();

  Future<bool> isVoiceHandsFreeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    await _maybeRefresh(prefs);
    return prefs.getBool(_voiceHandsFreeKey) ?? true;
  }

  Future<void> _maybeRefresh(SharedPreferences prefs) async {
    final lastChecked = prefs.getInt(_lastCheckedKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (lastChecked != null &&
        now - lastChecked < _checkInterval.inMilliseconds) {
      return;
    }

    try {
      final response = await _client
          .get(Uri.parse(ApiEndpoints.configFeatureFlags()))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final enabled = body['voiceHandsFreeEnabled'] as bool? ?? true;
      await prefs.setBool(_voiceHandsFreeKey, enabled);
      await prefs.setInt(_lastCheckedKey, now);
    } catch (_) {
      // Offline or backend unreachable — keep whatever was last cached
      // (or the true default for a brand-new install).
    }
  }
}
