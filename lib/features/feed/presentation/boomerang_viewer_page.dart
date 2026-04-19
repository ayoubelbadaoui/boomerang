import 'package:boomerang/core/utils/color_opacity.dart';
import 'package:boomerang/core/widgets/boomerang_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';
import 'package:boomerang/infrastructure/providers.dart';

class BoomerangViewerPage extends ConsumerStatefulWidget {
  const BoomerangViewerPage({super.key, required this.id, required this.data});
  final String id;
  final Map<String, dynamic> data;

  @override
  ConsumerState<BoomerangViewerPage> createState() =>
      _BoomerangViewerPageState();
}

class _BoomerangViewerPageState extends ConsumerState<BoomerangViewerPage>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _showHeart = false;
  bool _userPaused = false;
  bool _showPauseIcon = false;
  bool _showPosterOverlay = true;
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    final videoUrl = widget.data['videoUrl'] as String?;
    if (videoUrl != null && videoUrl.isNotEmpty) {
      _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl))
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() {});
          _controller?.setLooping(true);
          _controller?.setVolume(0.0);
          _controller?.play();
          _controller?.addListener(_onVideoTickForPoster);
          _schedulePosterFallback();
        });
    }
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoTickForPoster);
    _controller?.dispose();
    _anim.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  void _dismissPoster() {
    if (!_showPosterOverlay) return;
    _showPosterOverlay = false;
    _controller?.removeListener(_onVideoTickForPoster);
    if (mounted) setState(() {});
  }

  void _onVideoTickForPoster() {
    final c = _controller;
    if (c == null) return;
    final v = c.value;
    if (!v.isInitialized) return;
    if (!v.isBuffering && (v.isPlaying || v.position > Duration.zero)) {
      _dismissPoster();
    }
  }

  void _schedulePosterFallback() {
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      if (_controller?.value.isInitialized == true) _dismissPoster();
    });
  }

  void _onTap() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final wasPlaying = c.value.isPlaying;
    if (wasPlaying) {
      c.pause();
    } else {
      c.play();
    }
    setState(() {
      _userPaused = wasPlaying;
      _showPauseIcon = true;
    });
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showPauseIcon = false);
    });
  }

  void _onDoubleTap() async {
    setState(() => _showHeart = true);
    _anim.forward(from: 0);
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid != null) {
      await ref
          .read(boomerangRepoProvider)
          .toggleLike(boomerangId: widget.id, userId: uid);
    }
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() => _showHeart = false);
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.data['imageUrl'] as String?;
    final hasVideo = _controller != null && _controller!.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _onTap,
              onDoubleTap: _onDoubleTap,
              behavior: HitTestBehavior.opaque,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasVideo)
                    FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: _controller!.value.size.width,
                        height: _controller!.value.size.height,
                        child: VideoPlayer(_controller!),
                      ),
                    )
                  else
                    Container(color: Colors.black),
                  if (image != null &&
                      image.isNotEmpty &&
                      _showPosterOverlay)
                    AnimatedOpacity(
                      opacity: _showPosterOverlay ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 180),
                      child: Image.network(
                        image,
                        fit: BoxFit.cover,
                        cacheWidth: (MediaQuery.sizeOf(context).width *
                                MediaQuery.devicePixelRatioOf(context))
                            .round(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_showHeart)
            Center(
              child: ScaleTransition(
                scale: Tween(begin: 0.6, end: 1.2).animate(
                  CurvedAnimation(parent: _anim, curve: Curves.easeOutBack),
                ),
                child: Icon(
                  Icons.favorite,
                  color: Colors.white.fade(0.9),
                  size: 100.r,
                ),
              ),
            ),
          if (_showPauseIcon)
            Center(
              child: AnimatedOpacity(
                opacity: _showPauseIcon ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: EdgeInsets.all(16.r),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _userPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    color: Colors.white,
                    size: 48.r,
                  ),
                ),
              ),
            ),
          BoomerangOverlay(boomerangId: widget.id, data: widget.data),
        ],
      ),
    );
  }
}
