import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/constants/api_endpoints.dart';
import 'auth_service.dart';

/// Service layer for the OCR feature (FR4.2/FR4.3). The app only runs text
/// recognition on-device (OcrDatasource, via Google ML Kit) — pulling
/// merchant/date/amount out of that raw text is business logic, so it's
/// sent here to the backend to parse, like every other network call.
class OcrService {
  final _authService = AuthService();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _authService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// POST /api/ocr/parse — sends the raw recognized text, gets back the
  /// parsed merchant/date/amount plus a receiptId to link to the expense
  /// once the user confirms and saves it.
  Future<Map<String, dynamic>> parseReceipt(String rawText) async {
    try {
      final response = await http.post(
        Uri.parse(ApiEndpoints.ocrParse()),
        headers: await _authHeaders(),
        body: jsonEncode({'rawText': rawText}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception(
          'Failed to parse receipt (status ${response.statusCode}): ${response.body}',
        );
      }
    } catch (e) {
      throw Exception('Error parsing receipt: $e');
    }
  }
}
