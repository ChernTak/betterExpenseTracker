import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../core/constants/api_endpoints.dart';
import '../auth_service.dart';

/// OTA delivery for the on-device receipt NER model (LayoutLMv3) — follows
/// `TierBInferenceService`'s pattern (versioned check throttled to once/day,
/// `SharedPreferences`-tracked version, app-documents-dir storage) with two
/// differences forced by this model being ~10,000x larger (153MB vs. 14KB):
///
/// - **Streamed to disk**, not buffered whole in memory
///   (`http.get(...).bodyBytes`, Tier B's approach, would hold the entire
///   153MB response in RAM at once).
/// - **No bundled-asset fallback.** Tier B ships a small default `.tflite`
///   in the APK so it always has *something* to run; bundling 153MB isn't
///   viable, so this is OTA-only — if nothing's been downloaded yet (or the
///   download/load fails), [loadInterpreter] returns null and the caller
///   (see plan Stage 6) treats that exactly like "v3 found nothing": skip
///   on-device extraction and rely entirely on the backend regex parser.
///
/// Downloads to a `.part` temp file first and renames it into place only
/// once the stream completes — a receipt scan happening mid-download (or a
/// dropped connection) must never leave a truncated file behind that a
/// later `Interpreter.fromFile` call would treat as a valid model.
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

  /// Returns null if no model has ever been successfully downloaded, or the
  /// file on disk fails to load (corrupt/incompatible) — the caller must
  /// treat that as "on-device extraction unavailable this time" and fall
  /// back to the backend regex parser, not throw.
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
