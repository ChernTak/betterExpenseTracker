import 'package:vosk_flutter_2/vosk_flutter_2.dart';

/// Resolves the on-device path to the bundled Vosk wake-word model
/// (assets/models/README.md explains how it got there — it's a manual
/// download, not fetched by `pub get`).
///
/// vosk_flutter_2's own [ModelLoader] already does the actual work: Vosk's
/// native loader needs a real filesystem path (it can't read straight out
/// of Flutter's compiled asset bundle, e.g. a compressed APK entry on
/// Android), so [ModelLoader.loadFromAssets] unzips the bundled asset into
/// the app's documents directory the first time and reuses that extracted
/// copy on every later call. This class only adds a clearer error message
/// pointing at the manual-download step when that asset is missing.
class VoiceModelProvisioner {
  // Tried en-us-0.22-lgraph (~128MB) on 2026-09-05/06 to fix the small
  // model's poor vocabulary accuracy (e.g. "twenty ringgit" -> "the ring
  // it") — reverted after on-device testing: the lgraph model pushed CPU to
  // 90-160%+ and RAM to ~850MB on a Pixel 9a, and produced zero transcripts
  // across five clean attempts (vs. a working, if imperfect, transcript on
  // essentially the first attempt with this small model). It's too heavy to
  // decode in real time on this hardware — worse than low accuracy is no
  // result at all. Back to the small model.
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
