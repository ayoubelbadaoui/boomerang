import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AudioMessagePlayer extends StatefulWidget {
  const AudioMessagePlayer({
    super.key,
    required this.url,
    required this.durationMs,
    required this.isMine,
    required this.messageId,
  });

  final String url;
  final int durationMs;
  final bool isMine;
  final String messageId;

  @override
  State<AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<AudioMessagePlayer> {
  // Player is created lazily on first tap. Eager construction as a field
  // initializer previously triggered `GlobalAudioScope.ensureInitialized`
  // on every bubble build, which throws MissingPluginException if the
  // audioplayers native side isn't reachable (e.g. stale build, or while
  // the Flutter engine is still attaching plugins). Deferring it makes
  // listing the chat a read-only operation again.
  AudioPlayer? _player;
  final List<StreamSubscription<Object?>> _subs = [];

  bool _playing = false;
  bool _busy = false;
  bool _unavailable = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  late final List<double> _bars;

  @override
  void initState() {
    super.initState();
    _duration = Duration(milliseconds: widget.durationMs);
    _bars = _generateBars(widget.messageId);
  }

  List<double> _generateBars(String seed) {
    final rng = Random(seed.hashCode);
    return List.generate(28, (_) => 0.2 + rng.nextDouble() * 0.8);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _player?.dispose();
    super.dispose();
  }

  /// Create the native player on first use so a missing or still-attaching
  /// plugin can't crash widget construction. Returns null (and flips the
  /// bubble to an "unavailable" state) if the plugin simply isn't there.
  Future<AudioPlayer?> _ensurePlayer() async {
    if (_player != null) return _player;
    try {
      final p = AudioPlayer();
      _subs.add(p.onPositionChanged.listen((pos) {
        if (mounted) setState(() => _position = pos);
      }));
      _subs.add(p.onPlayerStateChanged.listen((s) {
        if (mounted) setState(() => _playing = s == PlayerState.playing);
      }));
      _subs.add(p.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _position = Duration.zero);
      }));
      _player = p;
      return p;
    } on MissingPluginException {
      if (mounted) setState(() => _unavailable = true);
      return null;
    } catch (_) {
      if (mounted) setState(() => _unavailable = true);
      return null;
    }
  }

  Future<void> _toggle() async {
    if (_busy || _unavailable) return;
    setState(() => _busy = true);
    try {
      final p = await _ensurePlayer();
      if (p == null) {
        _showUnavailable();
        return;
      }
      if (_playing) {
        await p.pause();
      } else {
        await p.play(UrlSource(widget.url));
      }
    } on MissingPluginException {
      if (mounted) setState(() => _unavailable = true);
      _showUnavailable();
    } catch (_) {
      // Generic playback error — silent; UI stays in non-playing state.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showUnavailable() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Audio playback isn't available right now. Try reopening the app.",
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.isMine ? Colors.white : Colors.black87;
    final barActiveColor =
        widget.isMine ? Colors.white : Theme.of(context).colorScheme.primary;
    final barInactiveColor = widget.isMine
        ? Colors.white.withValues(alpha: 0.4)
        : Colors.grey.shade300;
    final textColor = widget.isMine
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.grey.shade600;

    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _unavailable ? _showUnavailable : _toggle,
          child: Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.isMine
                  ? Colors.white.withValues(alpha: 0.2)
                  : Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.1),
            ),
            child: _busy
                ? Padding(
                    padding: EdgeInsets.all(8.w),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.w,
                      color: iconColor,
                    ),
                  )
                : Icon(
                    _unavailable
                        ? Icons.error_outline_rounded
                        : (_playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded),
                    color: iconColor,
                    size: 22.sp,
                  ),
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 24.h,
                child: CustomPaint(
                  size: Size(double.infinity, 24.h),
                  painter: _WaveformPainter(
                    bars: _bars,
                    progress: progress,
                    activeColor: barActiveColor,
                    inactiveColor: barInactiveColor,
                  ),
                ),
              ),
              SizedBox(height: 2.h),
              Text(
                _playing
                    ? _formatDuration(_position)
                    : _formatDuration(_duration),
                style: TextStyle(fontSize: 10.sp, color: textColor),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.bars,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  final List<double> bars;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / (bars.length * 2 - 1);
    final activePaint = Paint()..color = activeColor;
    final inactivePaint = Paint()..color = inactiveColor;

    for (int i = 0; i < bars.length; i++) {
      final x = i * barWidth * 2;
      final barHeight = bars[i] * size.height;
      final y = (size.height - barHeight) / 2;
      final isActive = (i / bars.length) <= progress;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          Radius.circular(barWidth / 2),
        ),
        isActive ? activePaint : inactivePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor;
}
