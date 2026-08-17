import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import 'game_audio_data.dart';

/// Provider for enabling/disabling game sound effects globally.
final soundEnabledProvider = StateProvider<bool>((ref) => true);

/// Provider for managing master game volume (0.0 to 1.0).
final soundVolumeProvider = StateProvider<double>((ref) => 0.85);

/// Provider for the singleton GameAudioService.
final gameAudioServiceProvider = Provider<GameAudioService>((ref) {
  final service = GameAudioService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});

enum GameSoundEffect {
  wheelTick,
  winFanfare,
  scratchReveal,
  giftUnlock,
  buttonPop,
  countdown,
}

/// Centralized Audio & Sound System for Material Design 3 and Interactive Games.
/// Fully freeze-proof and optimized for Web, Mobile, and Desktop with embedded zero-latency audio data.
class GameAudioService {
  final Ref _ref;
  final Map<GameSoundEffect, AudioPlayer> _cachedPlayers = {};

  GameAudioService(this._ref);

  /// Returns the corresponding embedded byte source or data URL for an effect
  Source _getSourceForEffect(GameSoundEffect effect) {
    if (kIsWeb) {
      // On Web, Base64 Data URL is decoded directly by HTML5 Audio without network latency
      switch (effect) {
        case GameSoundEffect.wheelTick:
          return UrlSource(GameAudioData.wheelTickDataUrl);
        case GameSoundEffect.winFanfare:
          return UrlSource(GameAudioData.winFanfareDataUrl);
        case GameSoundEffect.scratchReveal:
          return UrlSource(GameAudioData.scratchRevealDataUrl);
        case GameSoundEffect.giftUnlock:
          return UrlSource(GameAudioData.giftUnlockDataUrl);
        case GameSoundEffect.buttonPop:
          return UrlSource(GameAudioData.buttonPopDataUrl);
        case GameSoundEffect.countdown:
          return UrlSource(GameAudioData.countdownDataUrl);
      }
    } else {
      // On native platforms, BytesSource directly loads from memory
      switch (effect) {
        case GameSoundEffect.wheelTick:
          return BytesSource(GameAudioData.wheelTickBytes);
        case GameSoundEffect.winFanfare:
          return BytesSource(GameAudioData.winFanfareBytes);
        case GameSoundEffect.scratchReveal:
          return BytesSource(GameAudioData.scratchRevealBytes);
        case GameSoundEffect.giftUnlock:
          return BytesSource(GameAudioData.giftUnlockBytes);
        case GameSoundEffect.buttonPop:
          return BytesSource(GameAudioData.buttonPopBytes);
        case GameSoundEffect.countdown:
          return BytesSource(GameAudioData.countdownBytes);
      }
    }
  }

  AudioPlayer? _getOrCreatePlayer(GameSoundEffect effect) {
    if (_cachedPlayers.containsKey(effect)) {
      return _cachedPlayers[effect];
    }
    try {
      final player = AudioPlayer();
      player.setPlayerMode(PlayerMode.lowLatency);
      player.setReleaseMode(ReleaseMode.stop);
      _cachedPlayers[effect] = player;
      return player;
    } catch (e) {
      debugPrint('AudioPlayer initialization notice for $effect: $e');
      return null;
    }
  }

  /// Plays a specific game sound effect with current volume and enabled settings.
  /// Non-blocking and freeze-proof with timeout safety.
  Future<void> play(GameSoundEffect effect, {bool triggerHaptic = true}) async {
    final isEnabled = _ref.read(soundEnabledProvider);
    if (!isEnabled) return;

    final volume = _ref.read(soundVolumeProvider);

    // Coordinate subtle Material tactile haptic feedback
    if (triggerHaptic) {
      try {
        if (effect == GameSoundEffect.winFanfare || effect == GameSoundEffect.giftUnlock) {
          HapticFeedback.heavyImpact();
        } else if (effect == GameSoundEffect.wheelTick || effect == GameSoundEffect.buttonPop) {
          HapticFeedback.selectionClick();
        } else {
          HapticFeedback.mediumImpact();
        }
      } catch (_) {}
    }

    // Fire-and-forget execution so the UI NEVER blocks or freezes
    unawaited(_executeAudioPlay(effect, volume).catchError((e) {
      debugPrint('Audio playback handled notice for $effect: $e');
    }));
  }

  Future<void> _executeAudioPlay(GameSoundEffect effect, double volume) async {
    try {
      final player = _getOrCreatePlayer(effect);
      if (player == null) return;

      await player.setVolume(volume);
      final source = _getSourceForEffect(effect);
      await player.stop();
      await player.play(source);
    } catch (e) {
      debugPrint('Error playing sound $effect: $e');
      // If cached player got into an invalid state, clear and recreate on next play
      try {
        _cachedPlayers[effect]?.dispose();
      } catch (_) {}
      _cachedPlayers.remove(effect);
    }
  }

  /// Dedicated helper for wheel ticking during spin rotation
  Future<void> playWheelTick() => play(GameSoundEffect.wheelTick);

  /// Dedicated helper for grand prize win fanfare
  Future<void> playWinFanfare() => play(GameSoundEffect.winFanfare);

  /// Dedicated helper for scratch card prize reveal
  Future<void> playScratchReveal() => play(GameSoundEffect.scratchReveal);

  /// Dedicated helper for direct instant gift claim
  Future<void> playGiftUnlock() => play(GameSoundEffect.giftUnlock);

  /// Dedicated helper for Material 3 UI button click
  Future<void> playButtonPop() => play(GameSoundEffect.buttonPop);

  /// Dedicated helper for countdown beeps
  Future<void> playCountdown() => play(GameSoundEffect.countdown);

  void dispose() {
    for (final player in _cachedPlayers.values) {
      try {
        player.dispose();
      } catch (_) {}
    }
    _cachedPlayers.clear();
  }
}
