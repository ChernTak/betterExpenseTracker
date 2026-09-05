import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

/// Native on-device speech transcription (Android SpeechRecognizer / iOS
/// SFSpeechRecognizer via the speech_to_text package) for FR4.4 voice
/// expense logging.
///
/// Only captures the raw transcript — parsing amount/merchant/date out of
/// it happens in ExpenseNlpParserService, the same split OcrDatasource uses
/// for receipt scans (raw text extraction here, parsing elsewhere).
///
/// **Accumulates every final result, not just the first one, and falls back
/// to the last partial hypothesis when a final result is missing or empty.**
/// Two distinct on-device behaviors were confirmed on a physical device
/// (Pixel 9a, [ListenMode.dictation]), and this class has to handle both:
///
/// 1. One continuous utterance segmented into several separate `onResults`
///    (final) callbacks — e.g. "spent twenty ringgit" as one final result,
///    then "at starbucks" as a second, each carrying only that segment's
///    text, not the whole session's (confirmed by reading the plugin's
///    native Android source — `updateResults`/`onResults` in
///    SpeechToTextPlugin.kt passes through exactly what
///    `SpeechRecognizer.RESULTS_RECOGNITION` gave it for that segment). An
///    earlier version of this class completed on the *first* final result
///    and discarded everything after it — the actual mechanism behind "the
///    app mostly can't detect what I said" reports; it wasn't failing to
///    hear the rest of the sentence, it was hearing it and throwing it away.
/// 2. Separately (also confirmed via on-device logging): a session can
///    deliver a *correct, complete* sequence of non-final partial results
///    (e.g. "Bring" -> "Bring it" -> "Bring it at" -> "Bring it at
///    Starbucks") and then, seconds later — after the `done` status has
///    already fired — a lone `finalResult: true` callback with an **empty**
///    `recognizedWords`. Relying on final results alone loses real,
///    already-heard speech in this case. So the last non-empty partial is
///    tracked as a fallback and only discarded once a *non-empty* final
///    result actually commits its segment.
class VoiceDatasource {
  final SpeechToText _speech = SpeechToText();
  bool _available = false;

  // The single onStatus listener speech_to_text supports is registered once
  // at initialize() time and lives for this object's whole lifetime; each
  // listenOnce() call points it at that call's own completion logic so the
  // 'done' status (Android's authoritative "all results delivered, nothing
  // more is coming" signal — see the package's initialize() doc comment)
  // resolves the right pending listen.
  void Function(String status)? _onStatusChange;

  Future<bool> _ensureInitialized() async {
    if (_available) return true;
    _available = await _speech.initialize(
      onStatus: (status) => _onStatusChange?.call(status),
    );
    return _available;
  }

  /// Listens for a single spoken utterance and returns its accumulated
  /// transcript (every final-result segment joined with spaces, in the
  /// order Android delivered them, falling back to the last partial
  /// hypothesis for a segment whose final result was missing or empty —
  /// see the class doc comment), or null if speech recognition isn't
  /// available on this device, the user denied the mic/speech permission,
  /// or nothing was understood before the pause/listen timeout elapsed.
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

    final buffer = StringBuffer();
    // The latest non-empty partial hypothesis for whatever segment hasn't
    // been committed to buffer by a non-empty final result yet — see the
    // class doc comment's case 2. Reset once a non-empty final commits.
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

    // 'done' fires once the platform has delivered every result for this
    // session (including after a manual stop() — see its doc comment) and
    // won't deliver any more, whether or not any speech was actually
    // recognized (a doneNoResult session is normalized to 'done' by the
    // plugin itself). That makes it the right single signal to resolve on,
    // instead of guessing from individual result events.
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

    // Safety net: if 'done' never arrives (e.g. the platform callback
    // itself misbehaves), stop manually so callers aren't left waiting
    // indefinitely — this races against the normal 'done' path but finish()
    // is a no-op once the completer has already resolved either way.
    unawaited(
      Future.delayed(listenFor + const Duration(seconds: 2), () async {
        if (completer.isCompleted) return;
        await _speech.stop();
        finish();
      }),
    );

    return completer.future;
  }

  /// Ends listening early and delivers whatever was heard so far as the
  /// final result — unlike [cancel], which discards it. Lets a caller offer
  /// a manual "Stop" control instead of making the user wait out the full
  /// [listenFor]/[pauseFor] window on every attempt. Safe to call when not
  /// currently listening (mirrors [SpeechToText.stop]'s own no-op guard).
  Future<void> stop() => _speech.stop();

  Future<void> cancel() => _speech.cancel();

  void dispose() => _speech.cancel();
}
