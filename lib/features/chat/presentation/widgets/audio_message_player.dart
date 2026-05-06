import 'dart:math';

import 'package:boomerang/features/chat/application/chat_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AudioMessagePlayer extends ConsumerStatefulWidget {
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
  ConsumerState<AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends ConsumerState<AudioMessagePlayer> {
  late final List<double> _bars;

  @override
  void initState() {
    super.initState();
    _bars = _generateBars(widget.messageId);
  }

  List<double> _generateBars(String seed) {
    final rng = Random(seed.hashCode);
    return List.generate(28, (_) => 0.2 + rng.nextDouble() * 0.8);
  }

  Future<void> _toggle() async {
    final playback = ref.read(voiceMessagePlaybackProvider);
    if (playback.unavailable) {
      _showUnavailable();
      return;
    }
    await ref.read(voiceMessagePlaybackProvider.notifier).toggle(
          messageId: widget.messageId,
          url: widget.url,
          durationMs: widget.durationMs,
        );
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
    final playback = ref.watch(voiceMessagePlaybackProvider);
    final isActive = playback.activeMessageId == widget.messageId;
    final playing = isActive && playback.isPlaying;
    final busy = playback.busyMessageId == widget.messageId;
    final unavailable = playback.unavailable;

    final duration = Duration(milliseconds: widget.durationMs);
    final displayDuration =
        isActive && playback.duration > Duration.zero ? playback.duration : duration;
    final position = isActive ? playback.position : Duration.zero;

    final iconColor = widget.isMine ? Colors.white : Colors.black87;
    final barActiveColor =
        widget.isMine ? Colors.white : Theme.of(context).colorScheme.primary;
    final barInactiveColor = widget.isMine
        ? Colors.white.withValues(alpha: 0.4)
        : Colors.grey.shade300;
    final textColor = widget.isMine
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.grey.shade600;

    final progress = displayDuration.inMilliseconds > 0
        ? position.inMilliseconds / displayDuration.inMilliseconds
        : 0.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: unavailable ? _showUnavailable : _toggle,
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
            child: busy
                ? Padding(
                    padding: EdgeInsets.all(8.w),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.w,
                      color: iconColor,
                    ),
                  )
                : Icon(
                    unavailable
                        ? Icons.error_outline_rounded
                        : (playing
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
                    progress: progress.clamp(0.0, 1.0),
                    activeColor: barActiveColor,
                    inactiveColor: barInactiveColor,
                  ),
                ),
              ),
              SizedBox(height: 2.h),
              Text(
                playing
                    ? _formatDuration(position)
                    : _formatDuration(displayDuration),
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
