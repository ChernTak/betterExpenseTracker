import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

/// Audible cues since the wake-word haptic alone goes unfelt in a bag/desk. Uses a fresh [AudioPlayer] per call (not shared) since tones can overlap and a shared player would cut one off.
class VoiceAudioFeedbackService {
  static const _wakeAsset = 'audio/voice_wake.wav';
  static const _successAsset = 'audio/voice_success.wav';
  static const _errorAsset = 'audio/voice_error.wav';

  Future<void> _play(String asset) async {
    final player = AudioPlayer(playerId: 'voice_feedback_${DateTime.now().microsecondsSinceEpoch}');
    try {
      await player.setPlayerMode(PlayerMode.lowLatency);
      // Subscribe before play() so a completion event during the platform-channel round-trip isn't missed (broadcast stream won't replay it).
      unawaited(player.onPlayerComplete.first.then((_) => player.dispose()));
      await player.play(AssetSource(asset));
    } catch (_) {
      // Best-effort only: never let a playback failure block the save/parse flow this is just decorating.
      await player.dispose();
    }
  }

  Future<void> playWake() => _play(_wakeAsset);

  Future<void> playSuccess() => _play(_successAsset);

  Future<void> playError() => _play(_errorAsset);
}
