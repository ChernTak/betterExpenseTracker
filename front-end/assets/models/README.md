# Bundled models

These are manual downloads, not fetched by `flutter pub get`. Both are
declared as assets in `pubspec.yaml` and must exist at build time.

## `tier_b_regressor.tflite`

Trained locally — see `ai/train_tier_b.py`. Not relevant to voice logging.

## `vosk-model-small-en-us-0.15.zip`

Powers both the offline "Ok App" wake-word listener (`WakeWordService`,
FR4.4) and full-utterance transcription (`VoskTranscriptionService`) —
Android only, see those classes' doc comments for why. Both share this one
model via `VoskModelRegistry`.

**Tried upgrading to `vosk-model-en-us-0.22-lgraph` (~128MB) on 2026-09-05/06**
to fix this small model's weak vocabulary accuracy (e.g. "twenty ringgit"
transcribed as "the ring it"). Reverted after on-device testing on a Pixel
9a: the bigger model pushed the app to 90-160%+ CPU and ~850MB RAM while
listening, and produced zero transcripts across five clean attempts —
apparently too heavy to decode audio in real time on this hardware. A
model that never returns a result is worse than one with mediocre accuracy,
so this stays on the small model. If retrying this on beefier hardware,
`VoiceModelProvisioner._assetZipPath` and this pubspec entry are the two
places to swap.

1. Download it yourself from the official Vosk models page:
   https://alphacephei.com/vosk/models
   Get **`vosk-model-small-en-us-0.15.zip`** (~40MB, English, small).
2. Drop the zip file, unmodified, directly into this folder
   (`front-end/assets/models/vosk-model-small-en-us-0.15.zip`) — do **not**
   unzip it yourself. `VoiceModelProvisioner` (via vosk_flutter_2's
   `ModelLoader`) unzips it into the app's documents directory itself the
   first time hands-free listening or voice transcription starts, because
   Vosk's native loader needs a real filesystem path and can't read straight
   out of Flutter's compiled asset bundle.
3. Run `flutter pub get` (only needed once, to pick up the pubspec asset
   entry) and rebuild the app.

Without this file, tapping the hands-free mic toggle or the Voice tab fails
with a message pointing back at this README instead of a cryptic archive
error.

This zip is a ~40MB binary — consider whether it belongs in git history at
all (a `.gitignore` entry plus this README's download instructions would
keep the repo smaller and let every contributor fetch their own copy).
