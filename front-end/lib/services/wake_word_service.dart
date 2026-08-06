import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:vosk_flutter_2/vosk_flutter_2.dart';

import 'voice_model_provisioner.dart';

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
/// detecting the wake phrase, never for open transcription (see
/// VoiceDatasource for that, which takes over once the wake word fires).
///
/// Platform scope, both deliberate:
/// - **Android only.** vosk_flutter_2 has no iOS implementation (its
///   pubspec.yaml declares only an `android` plugin entry) — [start] throws
///   [WakeWordUnsupportedPlatformException] on any other platform. iOS users
///   get the Voice tap-to-talk button on the Input screen instead
///   (VoiceDatasource, via speech_to_text, which does support iOS).
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

  final VoiceModelProvisioner _modelProvisioner;
  VoskFlutterPlugin? _vosk;

  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;
  StreamSubscription<String>? _resultSubscription;
  bool _listening = false;

  WakeWordService({VoiceModelProvisioner? modelProvisioner})
    : _modelProvisioner = modelProvisioner ?? VoiceModelProvisioner();

  bool get isListening => _listening;

  Future<void> _ensureInitialized() async {
    if (_speechService != null) return;

    // Vosk's wake-word engine is Android-only — see
    // WakeWordUnsupportedPlatformException's doc comment. Checked before
    // ever touching VoskFlutterPlugin.instance(), which throws a raw,
    // uncatchable-by-type UnsupportedError on other platforms.
    if (!Platform.isAndroid) throw WakeWordUnsupportedPlatformException();

    final modelPath = await _modelProvisioner.ensureModelExtracted();
    final vosk = _vosk ??= VoskFlutterPlugin.instance();
    _model = await vosk.createModel(modelPath);
    _recognizer = await vosk.createRecognizer(
      model: _model!,
      sampleRate: _sampleRate,
      grammar: _grammar,
    );
    _speechService = await vosk.initSpeechService(_recognizer!);
  }

  /// Starts (or resumes) continuous grammar-restricted listening.
  /// [onWakeWordDetected] fires once per detected "ok app" utterance;
  /// listening continues afterwards, so a caller handing off to full
  /// transcription must call [stop] itself from inside the callback to
  /// release the microphone before starting TranscriptionService.
  Future<void> start(void Function() onWakeWordDetected) async {
    await _ensureInitialized();
    if (_listening) return;

    _resultSubscription ??= _speechService!.onResult().listen((resultJson) {
      if (_extractText(resultJson) == _wakePhrase) onWakeWordDetected();
    });

    await _speechService!.start();
    _listening = true;
  }

  /// Stops listening and releases the microphone. Both OSes only allow one
  /// consumer of the mic at a time, so this must complete before
  /// TranscriptionService starts, and callers should call [start] again
  /// once transcription finishes to resume hands-free listening.
  Future<void> stop() async {
    if (!_listening) return;
    await _speechService?.stop();
    _listening = false;
  }

  Future<void> dispose() async {
    await _resultSubscription?.cancel();
    _resultSubscription = null;
    await _speechService?.dispose();
    await _recognizer?.dispose();
    _model?.dispose();
    _speechService = null;
    _recognizer = null;
    _model = null;
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
