import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import '../core/constants/api_endpoints.dart';
import 'auth_service.dart';

/// Dart-side bridge for the high-spend-area geofencing nudge. The actual
/// geofence registration and the ENTER-transition handling live natively
/// (see android/app/.../GeofenceManager.kt, GeofenceReceiver.kt) so they keep
/// working even when the Flutter engine isn't running — this service only
/// covers the foreground actions: requesting permission, fetching the
/// location list, and telling the native side to register/clear it.
class GeofenceService {
  static const _channel = MethodChannel('com.example.expense_tracker/geofencing');
  final _authService = AuthService();

  /// Requests background location permission (a second, separate prompt on
  /// Android 10+ after foreground location is already granted), and returns
  /// whether it was actually granted — the caller (profile_screen.dart)
  /// should not flip its toggle on unless this is true.
  Future<bool> requestBackgroundLocationPermission() async {
    final foreground = await Permission.locationWhenInUse.request();
    if (!foreground.isGranted) return false;

    final background = await Permission.locationAlways.request();
    return background.isGranted;
  }

  /// Enables the feature: caches this device's current auth token + API base
  /// URL natively (so GeofenceReceiver can still authenticate a backend call
  /// with no Flutter engine alive), fetches the high-risk-location list, and
  /// registers it as native geofences.
  Future<void> enable() async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('Not logged in');

    await _channel.invokeMethod('cacheCredentials', {
      'token': token,
      'baseUrl': ApiEndpoints.baseUrl,
    });

    final locations = await _fetchHighRiskLocations();
    await _channel.invokeMethod('registerGeofences', {
      'locations': locations
          .map(
            (loc) => {
              'locationId': loc['location_id'],
              'latitude': loc['latitude'],
              'longitude': loc['longitude'],
              'radiusMeters': loc['radius_meters'],
            },
          )
          .toList(),
    });
  }

  /// Disables the feature: unregisters all geofences and wipes the natively
  /// cached token/location list. Also called from AuthService.logout() so a
  /// logged-out session can't keep triggering authenticated calls in the
  /// background under a stale token.
  Future<void> disable() async {
    await _channel.invokeMethod('clearGeofencingData');
  }

  Future<List<Map<String, dynamic>>> _fetchHighRiskLocations() async {
    final token = await _authService.getToken();
    if (token == null) throw Exception('Not logged in');

    final response = await http.get(
      Uri.parse(ApiEndpoints.nudgeHighRiskLocations()),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch high-risk locations (status ${response.statusCode})');
    }
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }
}
