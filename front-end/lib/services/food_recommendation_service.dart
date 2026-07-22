import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/constants/api_endpoints.dart';
import 'auth_service.dart';

/// Service layer for the location-based food recommendation feature.
///
/// Sends the device's current coordinates to the backend, which computes
/// C_meal from the user's remaining food_dining budget, filters nearby
/// venues (Foursquare) to a walking radius and that cap, and returns a
/// ranked list. Screens should call this and only handle the resulting
/// data or the exception, never build the HTTP request themselves.
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
  }) async {
    try {
      final response = await http.get(
        Uri.parse(ApiEndpoints.recommendationsFood(lat: lat, lng: lng, radius: radius)),
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
}
