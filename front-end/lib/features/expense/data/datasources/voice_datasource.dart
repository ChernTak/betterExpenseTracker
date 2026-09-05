import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

/// Native on-device speech transcription; only captures the raw transcript, parsing happens in ExpenseNlpParserService. Accumulates every final result (one utterance can arrive as multiple onResults callbacks, and an earlier version that stopped at the first one silently dropped speech) and falls back to the last partial when a final result is missing or empty.
class VoiceDatasource {
  final SpeechToText _speech = SpeechToText();
  bool _available = false;

  // speech_to_text only supports one onStatus listener; each listenOnce() call repoints it at its own completion logic.
  void Function(String status)? _onStatusChange;

  Future<bool> _ensureInitialized() async {
    if (_available) return true;
    _available = await _speech.initialize(
      onStatus: (status) => _onStatusChange?.call(status),
    );
    return _available;
  }

  /// Listens for one utterance and returns the accumulated transcript, or null if unavailable/denied/timed out. [onDevice] forces local-only recognition and fails rather than falling back to server-side, so null doesn't always mean "no speech".
  Future<String?> listenOnce({
    Duration listenFor = const Duration(seconds: 12),
    Duration pauseFor = const Duration(seconds: 3),
    bool onDevice = true,
  }) async {
    if (!await _ensureInitialized()) return null;

    final buffer = StringBuffer();
    // Latest partial hypothesis not yet committed by a non-empty final result; reset once one commits.
    var pendingPartial = '';
    final completer = Completer<String?>();

    void finish() {
      if (completer.isCompleted) return;
      _onStatusChange = null;
      if (pendingPartial.isNotEmpty) {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(pendingPartial);
      }
      final text = buffer.toString().trim();
      completer.complete(text.isEmpty ? null : text);
    }

    // 'done' is the platform's single authoritative "no more results coming" signal, so resolve on it rather than guessing from individual results.
    _onStatusChange = (status) {
      if (status == SpeechToText.doneStatus) finish();
    };

    await _speech.listen(
      onResult: (result) {
        final text = result.recognizedWords.trim();
        if (!result.finalResult) {
          if (text.isNotEmpty) pendingPartial = text;
          return;
        }
        if (text.isEmpty) return; // leave pendingPartial as the fallback
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(text);
        pendingPartial = ''; // this segment is now committed via the final
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
        onDevice: onDevice,
        cancelOnError: true,
        listenFor: listenFor,
        pauseFor: pauseFor,
      ),
    );

    // Safety net in case 'done' never arrives; finish() is a no-op if already resolved.
    unawaited(
      Future.delayed(listenFor + const Duration(seconds: 2), () async {
        if (completer.isCompleted) return;
        await _speech.stop();
        finish();
      }),
    );

    return completer.future;
  }

  /// Ends listening early and keeps whatever was heard so far, unlike [cancel] which discards it.
  Future<void> stop() => _speech.stop();

  Future<void> cancel() => _speech.cancel();

  void dispose() => _speech.cancel();
}
