import 'package:vosk_flutter_2/vosk_flutter_2.dart';

import 'voice_model_provisioner.dart';

/// Loads the bundled Vosk model exactly once and shares the same [Model] instance, since WakeWordService re-inits on every stop/resume cycle and the model is a real tens-of-MB native object not worth reloading. The static Future itself is the cache, so concurrent callers await the same in-flight load.
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
