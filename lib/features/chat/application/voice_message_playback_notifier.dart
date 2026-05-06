import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:boomerang/core/audio/app_audio_session.dart';

class VoiceMessagePlaybackState {
  const VoiceMessagePlaybackState({
    this.activeMessageId,
    this.busyMessageId,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.unavailable = false,
  });

  /// Message currently bound to the shared player (playing or paused mid-clip).
  final String? activeMessageId;

  /// Which bubble is awaiting an async toggle (shows a spinner only there).
  final String? busyMessageId;

  final bool isPlaying;
  final Duration position;
  final Duration duration;

  final bool unavailable;

  VoiceMessagePlaybackState copyWith({
    String? activeMessageId,
    String? busyMessageId,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    bool? unavailable,
    bool clearActiveMessageId = false,
    bool clearBusyMessageId = false,
  }) {
    return VoiceMessagePlaybackState(
      activeMessageId:
          clearActiveMessageId ? null : (activeMessageId ?? this.activeMessageId),
      busyMessageId:
          clearBusyMessageId ? null : (busyMessageId ?? this.busyMessageId),
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      unavailable: unavailable ?? this.unavailable,
    );
  }
}

class VoiceMessagePlaybackNotifier
    extends StateNotifier<VoiceMessagePlaybackState> {
  VoiceMessagePlaybackNotifier() : super(const VoiceMessagePlaybackState());

  AudioPlayer? _player;
  final List<StreamSubscription<Object?>> _subs = [];
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _player?.dispose();
    _player = null;
    unawaited(configureAmbientAudioSession());
    super.dispose();
  }

  Future<bool> _ensurePlayer() async {
    if (_player != null) return true;
    try {
      final p = AudioPlayer();
      _subs.add(
        p.onPositionChanged.listen((pos) {
          if (_disposed) return;
          if (state.activeMessageId != null) {
            state = state.copyWith(position: pos);
          }
        }),
      );
      _subs.add(
        p.onPlayerStateChanged.listen((s) {
          if (_disposed) return;
          state = state.copyWith(isPlaying: s == PlayerState.playing);
        }),
      );
      _subs.add(
        p.onPlayerComplete.listen((_) async {
          await configureAmbientAudioSession();
          if (_disposed) return;
          state = state.copyWith(
            clearActiveMessageId: true,
            clearBusyMessageId: true,
            isPlaying: false,
            position: Duration.zero,
            duration: Duration.zero,
          );
        }),
      );
      _player = p;
      return true;
    } on MissingPluginException {
      state = state.copyWith(unavailable: true);
      return false;
    } catch (_) {
      state = state.copyWith(unavailable: true);
      return false;
    }
  }

  Future<void> toggle({
    required String messageId,
    required String url,
    required int durationMs,
  }) async {
    if (state.unavailable) return;
    if (state.busyMessageId != null) return;

    state = state.copyWith(busyMessageId: messageId);

    try {
      final ok = await _ensurePlayer();
      if (!ok || _player == null) {
        state = state.copyWith(clearBusyMessageId: true);
        return;
      }

      final p = _player!;
      final activeId = state.activeMessageId;
      final playing = state.isPlaying;

      if (activeId == messageId && playing) {
        await p.pause();
        await configureAmbientAudioSession();
        state = state.copyWith(
          isPlaying: false,
          clearBusyMessageId: true,
        );
        return;
      }

      if (activeId == messageId && !playing) {
        await configureVoiceMessagePlaybackAudioSession();
        await p.resume();
        state = state.copyWith(
          isPlaying: true,
          clearBusyMessageId: true,
        );
        return;
      }

      if (activeId != null) {
        await p.stop();
        await configureAmbientAudioSession();
      }

      await configureVoiceMessagePlaybackAudioSession();

      state = state.copyWith(
        activeMessageId: messageId,
        duration: Duration(milliseconds: durationMs),
        position: Duration.zero,
        isPlaying: false,
      );

      await p.play(UrlSource(url));
      state = state.copyWith(
        isPlaying: true,
        clearBusyMessageId: true,
      );
    } on MissingPluginException {
      state = state.copyWith(unavailable: true, clearBusyMessageId: true);
      await configureAmbientAudioSession();
    } catch (_) {
      await configureAmbientAudioSession();
      state = state.copyWith(
        clearActiveMessageId: true,
        clearBusyMessageId: true,
        isPlaying: false,
        position: Duration.zero,
      );
    }
  }
}
