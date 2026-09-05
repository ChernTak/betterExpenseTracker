import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/constants/api_endpoints.dart';
import 'auth_service.dart';

/// Sends device coordinates to the backend, which computes the meal budget cap and ranks nearby venues (OSM/Geoapify/Foursquare fallback pipeline).
class FoodRecommendationService {
  final _authService = AuthService();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _authService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// GET /api/recommendations/food?lat=&lng= — ranked nearby venues plus
  /// the current meal budget cap context.
  Future<Map<String, dynamic>> fetchRecommendations({
    required double lat,
    required double lng,
    double? radius,
    List<String>? cuisines,
    bool? halal,
    String? visitFilter,
  }) async {
    try {
      final response = await http.get(
        Uri.parse(ApiEndpoints.recommendationsFood(
          lat: lat,
          lng: lng,
          radius: radius,
          cuisines: cuisines,
          halal: halal,
          visitFilter: visitFilter,
        )),
        headers: await _authHeaders(),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return body;
      } else {
        throw Exception(body['message'] ?? 'Failed to fetch food recommendations');
      }
    } catch (e) {
      throw Exception('Error fetching food recommendations: $e');
    }
  }

  /// GET /api/recommendations/food/venues/:provider/:providerPlaceId — venue detail, served from backend cache when available to avoid re-hitting the source provider.
  Future<Map<String, dynamic>> fetchVenueDetail(String provider, String providerPlaceId) async {
    try {
      final response = await http.get(
        Uri.parse(ApiEndpoints.recommendationVenueDetail(provider, providerPlaceId)),
        headers: await _authHeaders(),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        return body;
      } else {
        throw Exception(body['message'] ?? 'Failed to fetch venue detail');
      }
    } catch (e) {
      throw Exception('Error fetching venue detail: $e');
    }
  }
}
