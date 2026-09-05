import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

/// Audible cues for FR4.4's hands-free voice pipeline — the wake-word
/// haptic (see VoiceCaptureController) tells the user something happened,
/// but not whether it went well, and haptics go unfelt in a bag or on a
/// desk. A short chime for each of the three moments that matter (wake
/// heard, expense saved, something went wrong) is the minimum needed for
/// this to be usable without looking at the screen, which is the entire
/// point of a hands-free feature.
///
/// Each call uses its own short-lived [AudioPlayer] (`PlayerMode.lowLatency`)
/// rather than one shared instance — these tones can overlap in principle
/// (e.g. a stray wake chime while a previous error tone is still finishing),
/// and a shared player would cut one off to start the next.
class VoiceAudioFeedbackService {
  static const _wakeAsset = 'audio/voice_wake.wav';
  static const _successAsset = 'audio/voice_success.wav';
  static const _errorAsset = 'audio/voice_error.wav';

  Future<void> _play(String asset) async {
    final player = AudioPlayer(playerId: 'voice_feedback_${DateTime.now().microsecondsSinceEpoch}');
    try {
      await player.setPlayerMode(PlayerMode.lowLatency);
      // Subscribe before play() so a clip that finishes during the
      // platform-channel round-trip of play() itself isn't missed — this is
      // a broadcast stream and won't replay a completion event that already
      // fired. Release the player once it's done rather than leaking one
      // per call — none of these tones run longer than ~0.5s.
      unawaited(player.onPlayerComplete.first.then((_) => player.dispose()));
      await player.play(AssetSource(asset));
    } catch (_) {
      // Best-effort only: a missing audio device, silent-mode edge case on
      // some OEM skins, or a plugin hiccup shouldn't ever block the actual
      // save/parse flow this is just decorating.
      await player.dispose();
    }
  }

  Future<void> playWake() => _play(_wakeAsset);

  Future<void> playSuccess() => _play(_successAsset);

  Future<void> playError() => _play(_errorAsset);
}
