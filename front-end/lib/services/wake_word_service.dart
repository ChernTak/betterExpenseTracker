import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:vosk_flutter_2/vosk_flutter_2.dart';

import 'vosk_model_registry.dart';

/// Thrown lazily on first use (not at construction) so callers on unsupported platforms (notably iOS, which vosk_flutter_2 doesn't ship) can catch this instead of crashing on startup.
class WakeWordUnsupportedPlatformException implements Exception {
  @override
  String toString() =>
      'Hands-free "Ok App" wake-word listening needs vosk_flutter_2, which '
      'only ships an Android implementation. Use the Voice tap-to-talk '
      'button on the Input screen instead on this platform.';
}

/// FR4.4 hands-free activation: listens locally for "Ok App" via a Vosk recognizer restricted to a two-entry grammar (cheap enough to run continuously, but only good for detecting the wake phrase). Actual transcription happens via VoiceDatasource/speech_to_text instead, since Vosk's open-vocabulary mode mangled loanwords and bigger models were too CPU-heavy on-device. Android only (no iOS vosk_flutter_2 build; iOS uses the tap-to-talk button), and foreground-process-lifetime only — no foreground service, so the OS can reclaim it and the user re-enables from MainShell's mic toggle. Also throws [MicrophoneAccessDeniedException] if mic permission was denied; callers should request it explicitly beforehand instead.
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

    // Checked before touching VoskFlutterPlugin.instance(), which throws a raw, uncatchable-by-type UnsupportedError on non-Android platforms.
    if (!Platform.isAndroid) throw WakeWordUnsupportedPlatformException();

    // Cached by VoskModelRegistry so repeated stop/start cycles don't reload the ~40MB native model each time.
    final model = await VoskModelRegistry.ensureLoaded();
    final vosk = VoskFlutterPlugin.instance();
    _recognizer = await vosk.createRecognizer(
      model: model,
      sampleRate: _sampleRate,
      grammar: _grammar,
    );
    _speechService = await vosk.initSpeechService(_recognizer!);
  }

  /// [onWakeWordDetected] fires once per utterance and listening continues, so the caller must call [stop] itself to free the mic before starting VoiceDatasource.
  Future<void> start(void Function() onWakeWordDetected) async {
    await _ensureInitialized();
    if (_listening) return;

    // Always a fresh subscription, not `??=` — an old one would be listening to a stream [stop] already disposed.
    _resultSubscription = _speechService!.onResult().listen((resultJson) {
      if (_extractText(resultJson) == _wakePhrase) onWakeWordDetected();
    });

    await _speechService!.start();
    _listening = true;
  }

  /// Disposes (not just stops) because vosk_flutter_2 only allows one native SpeechService globally — merely stopping threw INITIALIZE_FAIL on the next [start]. The trailing 400ms delay is an untuned settle window: on-device testing showed native stop() returns before the mic's AudioRecord is actually released, and starting another consumer immediately caused a crash/SIGSEGV race.
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

  // Note: doesn't dispose the underlying Model — VoskModelRegistry caches it for the app's whole lifetime.
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
