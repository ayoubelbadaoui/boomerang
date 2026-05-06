import 'package:audio_session/audio_session.dart';

/// Default session: mix with background music, respect the mute switch for
/// incidental app audio (aligned with [AVAudioSessionCategory.ambient]).
Future<void> configureAmbientAudioSession() async {
  try {
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.ambient,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.movie,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gainTransientMayDuck,
      ),
    );
  } catch (_) {}
}

/// Session for intentional voice-note playback: media-style output so the
/// hardware mute switch does not silence taps-to-play on iOS; still mixes
/// with other apps where the platform allows.
///
/// Android: `AndroidAudioUsage.media` with speech content type models
/// voice/media-style playback (subject to OEM focus and Do Not Disturb).
/// Strict DND may still limit audible output depending on system settings.
Future<void> configureVoiceMessagePlaybackAudioSession() async {
  try {
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ),
    );
    await session.setActive(true);
  } catch (_) {}
}
