import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';

import 'package:boomerang/features/feed/presentation/editor/boomerang_editor_page.dart';
import 'package:boomerang/infrastructure/providers.dart';

/// Lets the user pick which portion of a gallery-imported video becomes the
/// boomerang clip. Shows a full-screen preview and a filmstrip timeline with
/// two draggable handles (start / end). The selected window is clamped to
/// [minWindow]..[maxWindow] and the preview auto-loops the selection while
/// dragging.
///
/// On confirm the chosen window is hard-trimmed via FFmpeg and the user is
/// forwarded to [BoomerangEditorPage] with the resulting short clip.
class VideoTrimPage extends ConsumerStatefulWidget {
  const VideoTrimPage({
    super.key,
    required this.inputFile,
    this.minWindow = const Duration(milliseconds: 300),
    this.maxWindow = const Duration(milliseconds: 1500),
  });

  final File inputFile;
  final Duration minWindow;
  final Duration maxWindow;

  @override
  ConsumerState<VideoTrimPage> createState() => _VideoTrimPageState();
}

class _VideoTrimPageState extends ConsumerState<VideoTrimPage> {
  VideoPlayerController? _video;
  bool _ready = false;
  bool _processing = false;

  // Trim window in seconds, relative to the source video's timeline.
  double _startSec = 0;
  double _endSec = 0;

  // Cached source duration. Set once after the video initialises.
  double _durationSec = 0;

  // Thumbnails rendered behind the timeline.
  List<String> _thumbs = const [];
  bool _thumbsLoading = true;

  // Loops the selection; cancelled before navigation so we don't jank.
  Timer? _loopTicker;

  // Which handle is currently being dragged (for haptics / visual feedback).
  _Handle? _dragging;

  double get _minWindowSec => widget.minWindow.inMilliseconds / 1000.0;
  double get _maxWindowSec => widget.maxWindow.inMilliseconds / 1000.0;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    final c = VideoPlayerController.file(widget.inputFile);
    _video = c;
    try {
      await c.initialize();
    } catch (e) {
      if (!mounted) return;
      _fail('Could not open video: $e');
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }

    _durationSec = c.value.duration.inMilliseconds / 1000.0;
    _startSec = 0;
    // Default window: first maxWindow seconds (capped by duration).
    _endSec = _durationSec < _maxWindowSec ? _durationSec : _maxWindowSec;

    await c.setLooping(false);
    await c.setVolume(0);
    await c.seekTo(Duration.zero);
    await c.play();

    setState(() => _ready = true);
    _startLoopTicker();
    // Kick off thumbnails in the background — they're not blocking.
    unawaited(_loadThumbnails());
  }

  Future<void> _loadThumbnails() async {
    try {
      final thumbs = await ref
          .read(boomerangProcessorProvider)
          .extractTimelineThumbnails(
            widget.inputFile.path,
            durationSeconds: _durationSec,
            count: 8,
          );
      if (!mounted) return;
      setState(() {
        _thumbs = thumbs;
        _thumbsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _thumbsLoading = false);
    }
  }

  /// Drives the looping playback inside the selected window. Runs at ~30fps
  /// so it can detect when playback crosses the end handle and seek back.
  void _startLoopTicker() {
    _loopTicker?.cancel();
    _loopTicker = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final c = _video;
      if (c == null || !c.value.isInitialized) return;
      final pos = c.value.position.inMilliseconds / 1000.0;
      final endMs = _endSec;
      final startMs = _startSec;
      if (pos >= endMs || pos < startMs - 0.05) {
        c.seekTo(Duration(milliseconds: (startMs * 1000).round()));
      }
      if (mounted) setState(() {}); // for playhead redraw
    });
  }

  @override
  void dispose() {
    _loopTicker?.cancel();
    _video?.pause();
    _video?.dispose();
    super.dispose();
  }

  // ── Drag handling ─────────────────────────────────────────────────────

  /// Called when a handle drag resizes one edge of the window.
  ///
  /// Behavior:
  ///  - Growing past [maxWindow] is hard-clamped — you've hit the boomerang
  ///    length ceiling and the opposite edge should *not* move.
  ///  - Shrinking past [minWindow] pushes the opposite edge along instead of
  ///    freezing the handle in place. This is what makes a collapsed (min)
  ///    selection still translate when you keep dragging the stuck handles
  ///    further in the same direction — no dead stop.
  void _updateWindow({double? newStart, double? newEnd}) {
    final minW = _minWindowSec;
    final maxW = _maxWindowSec;

    double start = _startSec;
    double end = _endSec;

    if (newStart != null) {
      start = newStart;
      if (start < 0) start = 0;
      if (start > _durationSec - minW) start = _durationSec - minW;

      // Max-size ceiling: growing would exceed maxWindow → clamp start up.
      if (start < end - maxW) start = end - maxW;

      // Min-size floor: shrinking would fall below minWindow → push end
      // forward so the window translates instead of stalling.
      if (start > end - minW) {
        end = start + minW;
        if (end > _durationSec) {
          end = _durationSec;
          start = end - minW;
        }
      }
    } else if (newEnd != null) {
      end = newEnd;
      if (end > _durationSec) end = _durationSec;
      if (end < minW) end = minW;

      // Max-size ceiling.
      if (end > start + maxW) end = start + maxW;

      // Min-size floor: push start back so the window translates.
      if (end < start + minW) {
        start = end - minW;
        if (start < 0) {
          start = 0;
          end = start + minW;
        }
      }
    }

    if (start == _startSec && end == _endSec) return;

    setState(() {
      _startSec = start;
      _endSec = end;
    });

    _seekTo(newEnd != null ? end : start);
  }

  /// Translate the whole selection window so its new start is [newStart],
  /// keeping the current window size unchanged. Used when the user drags
  /// the middle of the selection.
  void _translateWindow(double newStart) {
    final size = _endSec - _startSec;
    double start = newStart;
    if (start < 0) start = 0;
    if (start > _durationSec - size) start = _durationSec - size;
    final end = start + size;

    if (start == _startSec && end == _endSec) return;

    setState(() {
      _startSec = start;
      _endSec = end;
    });

    _seekTo(start);
  }

  void _seekTo(double sec) {
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    c.seekTo(Duration(milliseconds: (sec * 1000).round()));
    if (!c.value.isPlaying) c.play();
  }

  // ── Confirm → trim via FFmpeg → editor ────────────────────────────────

  Future<void> _confirm() async {
    if (_processing || !_ready) return;
    setState(() => _processing = true);
    HapticFeedback.selectionClick();

    try {
      await _video?.pause();
      final proc = ref.read(boomerangProcessorProvider);
      final trimmedPath = await proc.trimToWindow(
        widget.inputFile.path,
        startSeconds: _startSec,
        durationSeconds: _endSec - _startSec,
      );

      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => BoomerangEditorPage(inputFile: File(trimmedPath)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not trim video: $e')),
      );
      await _video?.play();
    }
  }

  void _fail(String msg) {
    setState(() => _ready = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    Navigator.of(context).maybePop();
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = _video;
    final theme = Theme.of(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: Text(
          'Trim',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16.sp,
          ),
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 12.w),
            child: TextButton(
              onPressed: _processing || !_ready ? null : _confirm,
              style: TextButton.styleFrom(
                backgroundColor: _ready ? Colors.white : Colors.white24,
                foregroundColor: Colors.black,
                padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 6.h),
                shape: const StadiumBorder(),
                disabledBackgroundColor: Colors.white24,
                disabledForegroundColor: Colors.white54,
              ),
              child: _processing
                  ? SizedBox(
                      width: 16.w,
                      height: 16.w,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : Text(
                      'Next',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: c != null && _ready
                    ? AspectRatio(
                        aspectRatio: c.value.aspectRatio,
                        child: VideoPlayer(c),
                      )
                    : const CircularProgressIndicator(color: Colors.white),
              ),
            ),
            SizedBox(height: 8.h),
            _TimeLabels(
              startSec: _startSec,
              endSec: _endSec,
              duration: _durationSec,
              minWindow: _minWindowSec,
              maxWindow: _maxWindowSec,
              theme: theme,
            ),
            SizedBox(height: 8.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: _TimelineBar(
                thumbs: _thumbs,
                thumbsLoading: _thumbsLoading,
                startSec: _startSec,
                endSec: _endSec,
                duration: _durationSec,
                minWindowSec: _minWindowSec,
                maxWindowSec: _maxWindowSec,
                playheadSec: c?.value.position.inMilliseconds != null
                    ? c!.value.position.inMilliseconds / 1000.0
                    : _startSec,
                onStartDragStart: () {
                  HapticFeedback.selectionClick();
                  setState(() => _dragging = _Handle.start);
                },
                onEndDragStart: () {
                  HapticFeedback.selectionClick();
                  setState(() => _dragging = _Handle.end);
                },
                onWindowDragStart: () {
                  HapticFeedback.selectionClick();
                  setState(() => _dragging = _Handle.window);
                },
                onDragEnd: () {
                  setState(() => _dragging = null);
                  HapticFeedback.selectionClick();
                },
                onStartChange: (s) => _updateWindow(newStart: s),
                onEndChange: (e) => _updateWindow(newEnd: e),
                onWindowTranslate: _translateWindow,
                draggingHandle: _dragging,
              ),
            ),
            SizedBox(height: 12.h + safeBottom),
          ],
        ),
      ),
    );
  }
}

enum _Handle { start, end, window, pan }

// ──────────────────────────────────────────────────────────────────────────
// Time labels
// ──────────────────────────────────────────────────────────────────────────

class _TimeLabels extends StatelessWidget {
  const _TimeLabels({
    required this.startSec,
    required this.endSec,
    required this.duration,
    required this.minWindow,
    required this.maxWindow,
    required this.theme,
  });

  final double startSec;
  final double endSec;
  final double duration;
  final double minWindow;
  final double maxWindow;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final window = (endSec - startSec).clamp(0.0, 99.0);
    final atMax = (window - maxWindow).abs() < 0.02;
    final atMin = (window - minWindow).abs() < 0.02;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Row(
        children: [
          Text(
            _fmt(startSec),
            style: TextStyle(color: Colors.white70, fontSize: 11.sp),
          ),
          const Spacer(),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 3.h),
            decoration: BoxDecoration(
              color: atMax
                  ? Colors.amber.withValues(alpha: 0.2)
                  : atMin
                      ? Colors.redAccent.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Text(
              '${window.toStringAsFixed(1)}s',
              style: TextStyle(
                color: atMax
                    ? Colors.amberAccent
                    : atMin
                        ? Colors.redAccent
                        : Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 11.sp,
              ),
            ),
          ),
          const Spacer(),
          Text(
            _fmt(endSec),
            style: TextStyle(color: Colors.white70, fontSize: 11.sp),
          ),
        ],
      ),
    );
  }

  String _fmt(double s) {
    final t = Duration(milliseconds: (s * 1000).round());
    final mm = t.inMinutes.remainder(60).toString().padLeft(1, '0');
    final ss = t.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ms = (t.inMilliseconds.remainder(1000) / 100).floor();
    return '$mm:$ss.$ms';
  }
}

// ──────────────────────────────────────────────────────────────────────────
// Timeline bar — filmstrip + two handles
// ──────────────────────────────────────────────────────────────────────────

class _TimelineBar extends StatefulWidget {
  const _TimelineBar({
    required this.thumbs,
    required this.thumbsLoading,
    required this.startSec,
    required this.endSec,
    required this.duration,
    required this.minWindowSec,
    required this.maxWindowSec,
    required this.playheadSec,
    required this.onStartDragStart,
    required this.onEndDragStart,
    required this.onWindowDragStart,
    required this.onDragEnd,
    required this.onStartChange,
    required this.onEndChange,
    required this.onWindowTranslate,
    required this.draggingHandle,
  });

  final List<String> thumbs;
  final bool thumbsLoading;
  final double startSec;
  final double endSec;
  final double duration;
  final double minWindowSec;
  final double maxWindowSec;
  final double playheadSec;

  final VoidCallback onStartDragStart;
  final VoidCallback onEndDragStart;
  final VoidCallback onWindowDragStart;
  final VoidCallback onDragEnd;
  final ValueChanged<double> onStartChange;
  final ValueChanged<double> onEndChange;
  /// Receives the new absolute `start` time (seconds) that the window should
  /// translate to. The bar computes the delta internally, the page clamps.
  final ValueChanged<double> onWindowTranslate;
  final _Handle? draggingHandle;

  @override
  State<_TimelineBar> createState() => _TimelineBarState();
}

class _TimelineBarState extends State<_TimelineBar> {
  static const double _trackHeight = 60;
  static const double _handleWidth = 14;
  static const double _handleGrabRadiusPx = 26;
  // Fixed zoom: every second of video is this many screen pixels. With 100
  // px/s the max trim window (1.5s) is 150px wide and the min (0.3s) is
  // 30px wide — handles never visually collapse on top of each other,
  // regardless of how long the source video is. Long videos overflow the
  // viewport horizontally and the user pans the filmstrip to navigate.
  static const double _pxPerSec = 100;

  _Handle? _active;

  // Mid-drag anchors (stored at the moment the drag begins).
  double? _dragOriginContentPx; // for window translate
  double? _dragOriginStartSec;  // for window translate
  double? _panOriginViewPx;     // for pan
  double? _panOriginScrollPx;   // for pan

  // Internal horizontal scroll offset in content pixels.
  double _scrollPx = 0;

  // Remember the last-rendered viewport width so we can keep the selection
  // in view when the parent updates `startSec` / `endSec`.
  double _lastViewportW = 0;
  double _lastContentW = 0;

  @override
  void didUpdateWidget(covariant _TimelineBar old) {
    super.didUpdateWidget(old);
    // Auto-scroll only when the user is NOT actively dragging. During a
    // drag the math uses a fixed scroll snapshot as an anchor; changing
    // scroll mid-drag would make the selection "run away" from the
    // user's finger. Manual pans are still always possible via the pan
    // gesture outside the selection.
    if (_active != null) return;
    if (widget.startSec != old.startSec || widget.endSec != old.endSec) {
      _ensureSelectionVisible();
    }
  }

  void _ensureSelectionVisible() {
    if (_lastViewportW <= 0) return;
    final maxScroll =
        (_lastContentW - _lastViewportW).clamp(0.0, double.infinity);
    final startPx = widget.startSec * _pxPerSec;
    final endPx = widget.endSec * _pxPerSec;
    const pad = 24.0;
    double scroll = _scrollPx;
    if (startPx < scroll + pad) {
      scroll = (startPx - pad).clamp(0.0, maxScroll);
    } else if (endPx > scroll + _lastViewportW - pad) {
      scroll = (endPx - _lastViewportW + pad).clamp(0.0, maxScroll);
    }
    if (scroll != _scrollPx) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _scrollPx = scroll);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportW = constraints.maxWidth;
        final safeDuration = widget.duration <= 0 ? 1.0 : widget.duration;
        final contentW = safeDuration * _pxPerSec;
        final maxScroll = (contentW - viewportW).clamp(0.0, double.infinity);

        // Clamp persisted scroll to current bounds (content width can vary
        // while the video is still initialising).
        final scrollPx = _scrollPx.clamp(0.0, maxScroll);

        _lastViewportW = viewportW;
        _lastContentW = contentW;

        double secToContentPx(double s) => s * _pxPerSec;
        double contentPxToSec(double px) =>
            (px / _pxPerSec).clamp(0.0, safeDuration);

        final startContentPx = secToContentPx(widget.startSec);
        final endContentPx = secToContentPx(widget.endSec);
        final playheadContentPx = secToContentPx(
          widget.playheadSec.clamp(widget.startSec, widget.endSec),
        );

        // Positions in the viewport (what the user sees / taps on).
        final startViewPx = startContentPx - scrollPx;
        final endViewPx = endContentPx - scrollPx;
        final playheadViewPx = playheadContentPx - scrollPx;

        void startDrag(double viewPx) {
          final contentPx = viewPx + scrollPx;
          final toStart = (contentPx - startContentPx).abs();
          final toEnd = (contentPx - endContentPx).abs();

          // Grab the closer handle if it's within the grab radius. At 100
          // px/s the window is at least 30px wide, so a fixed 26px radius
          // never swallows both handles.
          if (toStart < toEnd && toStart <= _handleGrabRadiusPx) {
            _active = _Handle.start;
            widget.onStartDragStart();
            return;
          }
          if (toEnd < toStart && toEnd <= _handleGrabRadiusPx) {
            _active = _Handle.end;
            widget.onEndDragStart();
            return;
          }

          // Touch inside the selection (not on a handle) translates the
          // window. Anywhere outside the selection pans the filmstrip so
          // the user can navigate a long video.
          if (contentPx > startContentPx && contentPx < endContentPx) {
            _active = _Handle.window;
            _dragOriginContentPx = contentPx;
            _dragOriginStartSec = widget.startSec;
            widget.onWindowDragStart();
          } else {
            _active = _Handle.pan;
            _panOriginViewPx = viewPx;
            _panOriginScrollPx = scrollPx;
          }
        }

        void updateDrag(double viewPx) {
          if (_active == _Handle.start) {
            // Let `_updateWindow` handle min/max bounds. Passing the raw
            // pointer-derived time (even past the opposite handle) means
            // over-drag cleanly translates the window at min size.
            final contentPx = viewPx + scrollPx;
            widget.onStartChange(contentPxToSec(contentPx));
          } else if (_active == _Handle.end) {
            final contentPx = viewPx + scrollPx;
            widget.onEndChange(contentPxToSec(contentPx));
          } else if (_active == _Handle.window &&
              _dragOriginContentPx != null &&
              _dragOriginStartSec != null) {
            final contentPx = viewPx + scrollPx;
            final deltaPx = contentPx - _dragOriginContentPx!;
            final deltaSec = deltaPx / _pxPerSec;
            widget.onWindowTranslate(_dragOriginStartSec! + deltaSec);
          } else if (_active == _Handle.pan &&
              _panOriginViewPx != null &&
              _panOriginScrollPx != null) {
            final deltaPx = viewPx - _panOriginViewPx!;
            final newScroll =
                (_panOriginScrollPx! - deltaPx).clamp(0.0, maxScroll);
            if (newScroll != _scrollPx) {
              setState(() => _scrollPx = newScroll);
            }
          }
        }

        void endDrag() {
          if (_active != null) {
            _active = null;
            _dragOriginContentPx = null;
            _dragOriginStartSec = null;
            _panOriginViewPx = null;
            _panOriginScrollPx = null;
            widget.onDragEnd();
            // After the drag is finished, if the selection has moved off
            // the visible viewport, scroll so the user can see the result.
            _ensureSelectionVisible();
          }
        }

        return SizedBox(
          height: _trackHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) => startDrag(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => updateDrag(d.localPosition.dx),
            onHorizontalDragEnd: (_) => endDrag(),
            onHorizontalDragCancel: endDrag,
            child: ClipRect(
              child: SizedBox(
                width: viewportW,
                height: _trackHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Filmstrip — a wide content layer that extends beyond
                    // the viewport and slides with the user's pan gesture.
                    Positioned(
                      left: -scrollPx,
                      top: 0,
                      bottom: 0,
                      width: contentW,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6.r),
                        child: _FilmstripBackground(
                          thumbs: widget.thumbs,
                          loading: widget.thumbsLoading,
                        ),
                      ),
                    ),
                    // Dim masks for regions outside the selection. Anchored
                    // in viewport coords so they always cover the full
                    // screen area even when the selection is scrolled away.
                    Positioned.fill(
                      left: 0,
                      right: (viewportW - startViewPx).clamp(0.0, viewportW),
                      child: IgnorePointer(child: _DimOverlay()),
                    ),
                    Positioned.fill(
                      left: endViewPx.clamp(0.0, viewportW),
                      right: 0,
                      child: IgnorePointer(child: _DimOverlay()),
                    ),
                    // Yellow selection border.
                    if (endViewPx > 0 && startViewPx < viewportW)
                      Positioned(
                        left: startViewPx.clamp(-_handleWidth, viewportW),
                        top: 0,
                        bottom: 0,
                        width: (endViewPx - startViewPx)
                            .clamp(0.0, viewportW + _handleWidth * 2),
                        child: IgnorePointer(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.amber,
                                width: widget.draggingHandle == _Handle.window
                                    ? 2.5
                                    : 2,
                              ),
                              borderRadius: BorderRadius.circular(6.r),
                              boxShadow:
                                  widget.draggingHandle == _Handle.window
                                      ? [
                                          BoxShadow(
                                            color: Colors.amber
                                                .withValues(alpha: 0.25),
                                            blurRadius: 10,
                                          ),
                                        ]
                                      : null,
                            ),
                          ),
                        ),
                      ),
                    // Playhead.
                    if (playheadViewPx >= 0 && playheadViewPx <= viewportW)
                      Positioned(
                        left: playheadViewPx - 1,
                        top: -3,
                        bottom: -3,
                        width: 2,
                        child: IgnorePointer(
                          child: Container(color: Colors.white),
                        ),
                      ),
                    // Start handle — purely visual.
                    Positioned(
                      left: startViewPx - _handleWidth / 2,
                      top: -6,
                      bottom: -6,
                      width: _handleWidth,
                      child: IgnorePointer(
                        child: _HandleVisual(
                          side: _Handle.start,
                          active: widget.draggingHandle == _Handle.start,
                        ),
                      ),
                    ),
                    // End handle — purely visual.
                    Positioned(
                      left: endViewPx - _handleWidth / 2,
                      top: -6,
                      bottom: -6,
                      width: _handleWidth,
                      child: IgnorePointer(
                        child: _HandleVisual(
                          side: _Handle.end,
                          active: widget.draggingHandle == _Handle.end,
                        ),
                      ),
                    ),
                    // Left affordance: when there's scrollable content to
                    // the left of the viewport, show a subtle chevron so
                    // the user knows they can pan to it.
                    if (scrollPx > 2)
                      Positioned(
                        left: 4,
                        top: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: Icon(
                            Icons.chevron_left,
                            size: 18,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                    if (scrollPx < maxScroll - 2)
                      Positioned(
                        right: 4,
                        top: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          child: Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DimOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(color: Colors.black.withValues(alpha: 0.55));
  }
}

class _FilmstripBackground extends StatelessWidget {
  const _FilmstripBackground({required this.thumbs, required this.loading});

  final List<String> thumbs;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (thumbs.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.grey.shade900,
              Colors.grey.shade800,
              Colors.grey.shade900,
            ],
          ),
        ),
        alignment: Alignment.center,
        child: loading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              )
            : null,
      );
    }
    return Row(
      children: [
        for (final p in thumbs)
          Expanded(
            child: Image.file(
              File(p),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => Container(
                color: Colors.grey.shade800,
              ),
            ),
          ),
      ],
    );
  }
}

/// Purely visual handle. All input is handled by the single `GestureDetector`
/// that wraps the whole track in `_TimelineBar`.
class _HandleVisual extends StatelessWidget {
  const _HandleVisual({required this.side, required this.active});

  final _Handle side;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        color: Colors.amber,
        borderRadius: BorderRadius.horizontal(
          left: side == _Handle.start ? const Radius.circular(6) : Radius.zero,
          right: side == _Handle.end ? const Radius.circular(6) : Radius.zero,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: Colors.amber.withValues(alpha: 0.35),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Center(
        child: Container(
          width: 2,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }
}
