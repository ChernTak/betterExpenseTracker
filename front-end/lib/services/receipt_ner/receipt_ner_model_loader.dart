import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../core/constants/api_endpoints.dart';
import '../auth_service.dart';

/// OTA delivery for the on-device receipt NER model (LayoutLMv3) — like `TierBInferenceService` but streamed to disk (not buffered in RAM) and OTA-only with no bundled fallback, since this model is ~10,000x larger (153MB vs 14KB); downloads to a `.part` file and renames into place only once complete, so a mid-download failure never leaves a truncated file that looks valid.
class ReceiptNerModelLoader {
  static Interpreter? _interpreter;

  static const _downloadedModelFileName = 'receipt_ner_model_downloaded.tflite';
  static const _versionPrefsKey = 'receipt_ner_model_version';
  static const _lastCheckedPrefsKey = 'receipt_ner_model_last_checked';
  static const _updateCheckInterval = Duration(days: 1);

  final _authService = AuthService();

  Future<Map<String, String>> _authHeaders() async {
    final token = await _authService.getToken();
    return {if (token != null) 'Authorization': 'Bearer $token'};
  }

  Future<File> _downloadedModelFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_downloadedModelFileName');
  }

  Future<void> _maybeDownloadNewerModel() async {
    final prefs = await SharedPreferences.getInstance();
    final lastChecked = prefs.getInt(_lastCheckedPrefsKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (lastChecked != null && now - lastChecked < _updateCheckInterval.inMilliseconds) {
      return; // checked recently enough — avoid a network round-trip on every scan
    }

    try {
      final versionResponse = await http.get(
        Uri.parse(ApiEndpoints.ocrModelVersion()),
        headers: await _authHeaders(),
      );
      if (versionResponse.statusCode != 200) return;

      final serverVersion = (jsonDecode(versionResponse.body) as Map<String, dynamic>)['version'] as String;
      await prefs.setInt(_lastCheckedPrefsKey, now);

      final downloaded = await _downloadedModelFile();
      if (prefs.getString(_versionPrefsKey) == serverVersion && await downloaded.exists()) {
        return; // already up to date
      }

      await _streamDownload(downloaded);
      await prefs.setString(_versionPrefsKey, serverVersion);
      _interpreter = null; // force the next load to pick up the new file
    } catch (_) {
      // offline, server unreachable, or download interrupted — keep using
      // whatever's already on disk (if anything)
    }
  }

  Future<void> _streamDownload(File destination) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(ApiEndpoints.ocrModelFile()));
      request.headers.addAll(await _authHeaders());
      final streamedResponse = await client.send(request);
      if (streamedResponse.statusCode != 200) return;

      final tempFile = File('${destination.path}.part');
      final sink = tempFile.openWrite();
      await streamedResponse.stream.pipe(sink);
      await sink.close();
      await tempFile.rename(destination.path);
    } finally {
      client.close();
    }
  }

  /// Returns null (never throws) if no model has been downloaded or the file fails to load — caller falls back to the backend regex parser.
  Future<Interpreter?> loadInterpreter() async {
    if (_interpreter != null) return _interpreter;

    await _maybeDownloadNewerModel();

    final downloaded = await _downloadedModelFile();
    if (!await downloaded.exists()) return null;

    try {
      return _interpreter = Interpreter.fromFile(downloaded);
    } catch (_) {
      return null;
    }
  }
}
