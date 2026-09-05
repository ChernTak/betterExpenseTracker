import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/constants/api_endpoints.dart';
import 'auth_service.dart';

/// OCR feature (FR4.2/FR4.3): text recognition runs on-device (ML Kit), but parsing merchant/date/amount is business logic done server-side.
class OcrService {
  final _authService = AuthService();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _authService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// POST /api/ocr/parse — returns parsed merchant/date/amount plus a receiptId to link once the expense is saved.
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
