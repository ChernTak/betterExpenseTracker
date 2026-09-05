import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:vosk_flutter_2/vosk_flutter_2.dart';

import 'vosk_model_registry.dart';

/// Thrown by [WakeWordService.start] on a platform vosk_flutter_2 has no
/// implementation for. Its pubspec.yaml only declares an `android` plugin
/// entry, and [VoskFlutterPlugin]'s constructor throws a raw
/// [UnsupportedError] for anything other than Android/Linux/Windows —
/// notably iOS. That constructor call happens lazily on first use here
/// (not eagerly at object-construction time), specifically so a caller on
/// an unsupported platform can catch this instead of crashing on startup.
class WakeWordUnsupportedPlatformException implements Exception {
  @override
  String toString() =>
      'Hands-free "Ok App" wake-word listening needs vosk_flutter_2, which '
      'only ships an Android implementation. Use the Voice tap-to-talk '
      'button on the Input screen instead on this platform.';
}

/// FR4.4 hands-free activation — continuously listens locally for the wake
/// phrase "Ok App" using a Vosk recognizer restricted to a two-entry
/// grammar (the phrase itself plus Vosk's `[unk]` catch-all for everything
/// else). Restricting the grammar instead of decoding against the full
/// ~40MB language model is what keeps this cheap enough to run
/// continuously — it also means this recognizer is only ever good for
/// detecting the wake phrase, never for open transcription. Once "Ok App"
/// fires, the actual expense sentence is captured by VoiceDatasource
/// (Android/iOS's own on-device SpeechRecognizer/SFSpeechRecognizer via the
/// speech_to_text package) instead of Vosk — tried Vosk's open-vocabulary
/// mode for that too (2026-09-05/06) and reverted it: small Vosk models
/// badly mangled vocabulary outside their training set (loanwords like
/// "ringgit"), and the one bigger model tried was too CPU-heavy to decode
/// in real time on a Pixel 9a. See VoiceDatasource's doc comment.
///
/// Platform scope, both deliberate:
/// - **Android only.** vosk_flutter_2 has no iOS implementation (its
///   pubspec.yaml declares only an `android` plugin entry) — [start] throws
///   [WakeWordUnsupportedPlatformException] on any other platform. iOS users
///   get the Voice tap-to-talk button on the Input screen instead — it never
///   needed Vosk in the first place, since transcription is VoiceDatasource
///   on both platforms.
/// - **Foreground-process-lifetime only**, even on Android — this
///   deliberately does NOT run as a foreground service to survive
///   indefinite screen-off/backgrounding, since that requires a background
///   isolate driving vosk_flutter_2's platform channel/FFI calls, which
///   isn't verifiable without testing on a real device. If the OS reclaims
///   the process, the user re-enables listening from MainShell's mic toggle
///   when they reopen the app.
///
/// [start] also throws [MicrophoneAccessDeniedException] (thrown by
/// vosk_flutter_2's initSpeechService) if the user has denied mic
/// permission — callers should request it explicitly beforehand instead of
/// relying on that exception as the primary permission flow.
class WakeWordService {
  static const _sampleRate = 16000;
  static const _wakePhrase = 'ok app';
  static const _grammar = [_wakePhrase, '[unk]'];

  Recognizer? _recognizer;
  SpeechService? _speechService;
  StreamSubscription<String>? _resultSubscription;
  bool _listening = false;

  bool get isListening => _listening;

  Future<void> _ensureInitialized() async {
    if (_speechService != null) return;

    // Vosk's wake-word engine is Android-only — see
    // WakeWordUnsupportedPlatformException's doc comment. Checked before
    // ever touching VoskFlutterPlugin.instance(), which throws a raw,
    // uncatchable-by-type UnsupportedError on other platforms.
    if (!Platform.isAndroid) throw WakeWordUnsupportedPlatformException();

    // Cached by VoskModelRegistry so repeated stop/start cycles across a
    // session (every wake-word handoff resumes this) don't reload the
    // ~40MB native model from scratch each time.
    final model = await VoskModelRegistry.ensureLoaded();
    final vosk = VoskFlutterPlugin.instance();
    _recognizer = await vosk.createRecognizer(
      model: model,
      sampleRate: _sampleRate,
      grammar: _grammar,
    );
    _speechService = await vosk.initSpeechService(_recognizer!);
  }

  /// Starts (or resumes) continuous grammar-restricted listening.
  /// [onWakeWordDetected] fires once per detected "ok app" utterance;
  /// listening continues afterwards, so a caller handing off to full
  /// transcription must call [stop] itself from inside the callback to
  /// release the microphone before starting VoiceDatasource's listen.
  Future<void> start(void Function() onWakeWordDetected) async {
    await _ensureInitialized();
    if (_listening) return;

    // Always a fresh subscription, not `??=` — [stop] disposes and nulls
    // _speechService (see its doc comment for why), so _ensureInitialized
    // creates a brand new one on every resume and any old subscription
    // would be listening to an already-disposed stream.
    _resultSubscription = _speechService!.onResult().listen((resultJson) {
      if (_extractText(resultJson) == _wakePhrase) onWakeWordDetected();
    });

    await _speechService!.start();
    _listening = true;
  }

  /// Stops listening and fully releases both the microphone and the
  /// underlying native SpeechService. Both OSes only allow one consumer of
  /// the mic at a time, so this must complete before VoiceDatasource starts
  /// its own listen, and callers should call [start] again once
  /// transcription finishes to resume hands-free listening.
  ///
  /// This disposes rather than just stopping — confirmed on a physical
  /// device: vosk_flutter_2's native layer only allows *one* SpeechService
  /// object to exist at all, globally, so a subsequent [start] call re-uses
  /// the same native slot. Merely stopping (not disposing) this one and
  /// then calling [start] again threw `PlatformException(INITIALIZE_FAIL,
  /// SpeechService instance already exist.)` — the native slot was never
  /// actually freed. Recognizer creation from an already-loaded Model (see
  /// VoskModelRegistry) is cheap, so paying that cost on every handoff is
  /// the correct fix here, not a workaround.
  ///
  /// Separately, also confirmed on a physical device (2026-08-28 logcat):
  /// vosk_flutter_2's native `SpeechService.stop()` returns to Dart before
  /// its background RecognizerThread has actually finished releasing the
  /// microphone's AudioRecord. A caller that immediately hands the mic to
  /// another consumer here can race that teardown and crash the whole
  /// process: `java.lang.RuntimeException: error reading audio buffer` at
  /// `SpeechService$RecognizerThread.run`, and separately a SIGSEGV inside
  /// `libvosk.so`'s `Recognizer::AcceptWaveform`. The fixed delay below is
  /// a pragmatic settle window for that race, not a real fix — the real fix
  /// belongs upstream in vosk_flutter_2 itself. 400ms is an untuned,
  /// conservative guess; shorten it only after confirming on-device that
  /// the crash doesn't recur.
  Future<void> stop() async {
    if (!_listening) return;
    await _resultSubscription?.cancel();
    _resultSubscription = null;
    await _speechService?.stop();
    await _speechService?.dispose();
    await _recognizer?.dispose();
    _speechService = null;
    _recognizer = null;
    _listening = false;
    await Future.delayed(const Duration(milliseconds: 400));
  }

  // Note: doesn't dispose the underlying Model — VoskModelRegistry caches
  // it for the app's whole lifetime, outliving any single recognizer built
  // from it.
  Future<void> dispose() async {
    await _resultSubscription?.cancel();
    _resultSubscription = null;
    await _speechService?.dispose();
    await _recognizer?.dispose();
    _speechService = null;
    _recognizer = null;
    _listening = false;
  }

  String? _extractText(String resultJson) {
    try {
      final decoded = jsonDecode(resultJson) as Map<String, dynamic>;
      final text = (decoded['text'] as String?)?.trim().toLowerCase();
      return (text == null || text.isEmpty) ? null : text;
    } catch (_) {
      return null;
    }
  }
}
