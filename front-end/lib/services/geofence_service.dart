import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import '../core/constants/api_endpoints.dart';
import 'auth_service.dart';

/// Geofence registration/ENTER handling live natively so they work without the Flutter engine running; this only covers foreground actions.
class GeofenceService {
  static const _channel = MethodChannel('com.example.expense_tracker/geofencing');
  final _authService = AuthService();

  /// Caller should only flip its toggle on if this returns true.
  Future<bool> requestBackgroundLocationPermission() async {
    final foreground = await Permission.locationWhenInUse.request();
    if (!foreground.isGranted) return false;

    final background = await Permission.locationAlways.request();
    return background.isGranted;
  }

  /// Caches auth token + API base URL natively so GeofenceReceiver can call the backend without the Flutter engine alive.
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

  /// Also called from AuthService.logout() so a stale token can't keep triggering background calls.
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
