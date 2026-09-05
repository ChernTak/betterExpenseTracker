import 'package:vosk_flutter_2/vosk_flutter_2.dart';

/// Resolves the path to the bundled Vosk model (manually downloaded, see assets/models/README.md, not fetched by `pub get`); wraps [ModelLoader.loadFromAssets] with a clearer error when that asset is missing.
class VoiceModelProvisioner {
  // Tried the larger lgraph model for better accuracy but reverted: it was too CPU/RAM-heavy for real-time decoding on a Pixel 9a and produced zero transcripts in testing.
  static const _assetZipPath = 'assets/models/vosk-model-small-en-us-0.15.zip';

  final ModelLoader _modelLoader;

  VoiceModelProvisioner({ModelLoader? modelLoader})
    : _modelLoader = modelLoader ?? ModelLoader();

  /// Returns the filesystem path to the extracted model directory.
  Future<String> ensureModelExtracted() async {
    try {
      return await _modelLoader.loadFromAssets(_assetZipPath);
    } catch (e) {
      throw StateError(
        'Could not load the Vosk wake-word model from $_assetZipPath ($e). '
        'It is a manual download, not fetched by `pub get` — see '
        'front-end/assets/models/README.md.',
      );
    }
  }
}
