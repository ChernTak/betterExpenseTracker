import 'package:vosk_flutter_2/vosk_flutter_2.dart';

import 'voice_model_provisioner.dart';

/// Loads the bundled Vosk model exactly once and hands the same [Model]
/// instance to every caller. [WakeWordService] is the only one today (Vosk
/// transcription for the actual expense sentence was tried and reverted —
/// see its doc comment — full transcription is VoiceDatasource/speech_to_text
/// now), but it re-runs its own init on every hands-free stop/resume cycle
/// within a session, and a Vosk model is a real (tens of MB) native object,
/// not something worth reloading each time.
///
/// The static Future itself is the cache: concurrent callers before the
/// first load finishes all await the same in-flight Future rather than
/// triggering redundant loads.
class VoskModelRegistry {
  static Future<Model>? _modelFuture;

  static Future<Model> ensureLoaded({VoiceModelProvisioner? provisioner}) {
    return _modelFuture ??= _load(provisioner ?? VoiceModelProvisioner());
  }

  static Future<Model> _load(VoiceModelProvisioner provisioner) async {
    final modelPath = await provisioner.ensureModelExtracted();
    return VoskFlutterPlugin.instance().createModel(modelPath);
  }
}
