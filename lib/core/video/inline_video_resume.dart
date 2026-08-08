import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';

/// Resumes muted inline / fullscreen looping after the platform player was
/// paused without our visibility state clearing — phone calls, audio-focus
/// interruptions, Control Center, and route overlays (`TickerMode` false).
class InlineVideoResumeBinder with WidgetsBindingObserver {
  InlineVideoResumeBinder({required this.onResumeRequested});

  final VoidCallback onResumeRequested;

  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  bool _observing = false;
  bool? _tickerEnabled;

  void start() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_listenInterruptions());
  }

  void stop() {
    if (!_observing) return;
    _observing = false;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_interruptionSub?.cancel());
    _interruptionSub = null;
    _tickerEnabled = null;
  }

  /// Call from [State.didChangeDependencies] so returning from a pushed route
  /// (fullscreen pager, sheets) restarts looping.
  void syncTickerMode(BuildContext context) {
    final enabled = TickerMode.of(context);
    final was = _tickerEnabled;
    _tickerEnabled = enabled;
    if (was == false && enabled) {
      onResumeRequested();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResumeRequested();
    }
  }

  Future<void> _listenInterruptions() async {
    try {
      final session = await AudioSession.instance;
      await _interruptionSub?.cancel();
      _interruptionSub = session.interruptionEventStream.listen((event) {
        // begin == true: call / focus loss (player may pause).
        // begin == false: interruption ended — restart if still "should play".
        if (!event.begin) {
          onResumeRequested();
        }
      });
    } catch (_) {
      // Audio session unavailable — lifecycle + ticker paths still apply.
    }
  }
}
