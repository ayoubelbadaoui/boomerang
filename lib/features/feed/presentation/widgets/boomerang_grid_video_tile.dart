import 'dart:async';

import 'package:boomerang/core/widgets/boomerang_grid_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:boomerang/core/video/boomerang_video_cache.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// A grid cell that shows the boomerang poster and, once the tile is
/// sufficiently visible, autoplays the clip muted and looping.
///
/// Visibility uses hysteresis + a delayed decoder release so brief scroll
/// flickers (and Discover masonry rebuilds) do not tear down playback and
/// make the whole grid look like it is refreshing.
class BoomerangGridVideoTile extends StatefulWidget {
  const BoomerangGridVideoTile({
    super.key,
    required this.postId,
    required this.videoUrl,
    required this.imageUrl,
    required this.borderRadius,
    this.cacheWidth,
    this.phaseShift = 0,

    /// Fraction of the tile that must be visible before playback starts.
    this.playThreshold = 0.4,

    /// Fraction below which playback pauses. Must be < [playThreshold].
    this.pauseThreshold = 0.15,
  });

  final String postId;
  final String? videoUrl;
  final String? imageUrl;
  final BorderRadius borderRadius;
  final int? cacheWidth;
  final double phaseShift;
  final double playThreshold;
  final double pauseThreshold;

  @override
  State<BoomerangGridVideoTile> createState() => _BoomerangGridVideoTileState();
}

class _BoomerangGridVideoTileState extends State<BoomerangGridVideoTile> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _videoReady = false;
  bool _initFailed = false;
  bool _visible = false;
  int _initGen = 0;
  Timer? _disposeTimer;

  static const _disposeDelay = Duration(milliseconds: 900);

  bool get _hasVideo =>
      widget.videoUrl != null && widget.videoUrl!.isNotEmpty;

  @override
  void didUpdateWidget(covariant BoomerangGridVideoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.videoUrl != oldWidget.videoUrl) {
      _initFailed = false;
      _cancelDisposeTimer();
      _disposeController();
      if (_visible && _hasVideo) _initController();
    }
  }

  void _cancelDisposeTimer() {
    _disposeTimer?.cancel();
    _disposeTimer = null;
  }

  void _scheduleDispose() {
    _cancelDisposeTimer();
    _disposeTimer = Timer(_disposeDelay, () {
      if (!mounted || _visible) return;
      _disposeController();
      if (mounted) setState(() {});
    });
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    final fraction = info.visibleFraction;
    if (!_hasVideo) {
      _visible = fraction >= widget.playThreshold;
      return;
    }

    if (!_visible && fraction >= widget.playThreshold) {
      _visible = true;
      _cancelDisposeTimer();
      if (!_initialized) {
        _initController();
      } else {
        _controller?.play();
      }
      return;
    }

    if (_visible && fraction < widget.pauseThreshold) {
      _visible = false;
      // Keep the decoded frame on screen; only release the decoder after the
      // tile has stayed offscreen long enough that scroll thrash is over.
      _controller?.pause();
      _scheduleDispose();
    }
  }

  Future<void> _initController() async {
    final url = widget.videoUrl;
    if (url == null || url.isEmpty) return;
    // Dispose any previous controller first: _disposeController bumps
    // _initGen, so it must run before we capture this attempt's generation
    // or the guards below would cancel our own init.
    _disposeController();
    final gen = _initGen;
    _videoReady = false;
    final controller = await BoomerangVideoCache.instance.createController(
      url,
    );
    if (!mounted || gen != _initGen || !_visible) {
      await controller.dispose();
      return;
    }
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted || gen != _initGen || !_visible) {
        await controller.dispose();
        if (_controller == controller) {
          _controller = null;
          _initialized = false;
          _videoReady = false;
        }
        return;
      }
      _initialized = true;
      await controller.setLooping(true);
      await controller.setVolume(0.0);
      if (_visible) await controller.play();
      if (mounted && gen == _initGen) setState(() => _videoReady = true);
    } catch (_) {
      if (mounted && gen == _initGen) setState(() => _initFailed = true);
    }
  }

  void _disposeController() {
    _initGen++;
    _controller?.dispose();
    _controller = null;
    _initialized = false;
    _videoReady = false;
  }

  @override
  void dispose() {
    _cancelDisposeTimer();
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showVideo =
        _videoReady && !_initFailed && _controller?.value.isInitialized == true;

    return VisibilityDetector(
      key: Key('bmg-grid-${widget.postId}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            BoomerangGridThumbnail(
              imageUrl: widget.imageUrl,
              borderRadius: BorderRadius.zero,
              cacheWidth: widget.cacheWidth,
              phaseShift: widget.phaseShift,
              usePlainNetwork: false,
            ),
            if (showVideo)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
