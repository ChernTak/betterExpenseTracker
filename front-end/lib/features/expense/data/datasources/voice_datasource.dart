import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

/// Native on-device speech transcription (Android SpeechRecognizer / iOS
/// SFSpeechRecognizer via the speech_to_text package) for FR4.4 voice
/// expense logging.
///
/// Only captures the raw transcript — parsing amount/merchant/date out of
/// it happens in ExpenseNlpParserService, the same split OcrDatasource uses
/// for receipt scans (raw text extraction here, parsing elsewhere).
class VoiceDatasource {
  final SpeechToText _speech = SpeechToText();
  bool _available = false;

  Future<bool> _ensureInitialized() async {
    if (_available) return true;
    _available = await _speech.initialize();
    return _available;
  }

  /// Listens for a single spoken utterance and returns its final
  /// transcript, or null if speech recognition isn't available on this
  /// device, the user denied the mic/speech permission, or nothing was
  /// understood before the pause/listen timeout elapsed.
  ///
  /// [onDevice] enforces local-only recognition (FR4.4's offline-first
  /// requirement) — on a device/OS version that can't do that, the listen
  /// attempt fails rather than silently falling back to server-side
  /// recognition, so a null result here doesn't always mean "no speech".
  Future<String?> listenOnce({
    Duration listenFor = const Duration(seconds: 12),
    Duration pauseFor = const Duration(seconds: 3),
    bool onDevice = true,
  }) async {
    if (!await _ensureInitialized()) return null;

    final completer = Completer<String?>();

    await _speech.listen(
      onResult: (result) {
        if (result.finalResult && !completer.isCompleted) {
          final text = result.recognizedWords.trim();
          completer.complete(text.isEmpty ? null : text);
        }
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

    // Safety net: if the platform never delivers a final result (e.g. dead
    // silence for the whole window), stop manually so callers aren't left
    // waiting indefinitely.
    return completer.future.timeout(
      listenFor + const Duration(seconds: 2),
      onTimeout: () async {
        await _speech.stop();
        return null;
      },
    );
  }

  Future<void> cancel() => _speech.cancel();

  void dispose() => _speech.cancel();
}
