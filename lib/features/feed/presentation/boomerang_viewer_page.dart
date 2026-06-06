import 'package:boomerang/core/utils/color_opacity.dart';
import 'package:boomerang/core/widgets/boomerang_overlay.dart';
import 'package:boomerang/features/feed/presentation/widgets/fullscreen_boomerang_media.dart';
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

  bool? _likedOverride;
  int? _likesOverride;
  bool _likeBusy = false;

  @override
  void initState() {
    super.initState();
    final seeded = resolveActivePostLikeUiState(
      ref.read(postLikeUiEntryProvider(widget.id)),
    );
    _likedOverride = seeded?.liked;
    _likesOverride = seeded?.likes;
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
    if (_canDismissPoster(v)) {
      _dismissPoster();
    }
  }

  bool _canDismissPoster(VideoPlayerValue v) {
    if (!v.isInitialized) return false;
    if (v.hasError) return true;
    final hasValidSize = v.size.width > 0 && v.size.height > 0;
    final hasProgress = v.position > Duration.zero;
    final hasDuration = v.duration > Duration.zero;
    return hasValidSize &&
        !v.isBuffering &&
        (hasProgress || v.isPlaying || !hasDuration);
  }

  void _schedulePosterFallback() {
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final value = _controller?.value;
      if (value != null && _canDismissPoster(value)) {
        _dismissPoster();
      }
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
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null || _likeBusy) return;
    final likedBy =
        (widget.data['likedBy'] as List?)?.cast<String>() ?? const <String>[];
    final wasLiked = _likedOverride ?? likedBy.contains(uid);
    final currentLikes = _likesOverride ?? (widget.data['likes'] ?? 0) as int;

    if (!wasLiked) {
      setState(() {
        _likedOverride = true;
        _likesOverride = currentLikes + 1;
      });
      ref
          .read(postLikeUiControllerProvider.notifier)
          .setStateForPost(
            postId: widget.id,
            liked: true,
            likes: currentLikes + 1,
          );
    }

    setState(() => _showHeart = true);
    _anim.forward(from: 0);

    if (wasLiked) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) setState(() => _showHeart = false);
      return;
    }

    final me = ref.read(currentUserProfileProvider).value;
    setState(() => _likeBusy = true);
    try {
      final result = await ref
          .read(boomerangRepoProvider)
          .setLike(
            boomerangId: widget.id,
            userId: uid,
            shouldLike: true,
            actorName:
                me != null
                    ? (me.nickname.isNotEmpty ? me.nickname : me.fullName)
                    : 'User',
            actorAvatar: me?.avatarUrl,
          );
      if (result != null && mounted) {
        setState(() {
          _likedOverride = result.liked;
          _likesOverride = result.likes;
        });
        ref
            .read(postLikeUiControllerProvider.notifier)
            .setStateForPost(
              postId: widget.id,
              liked: result.liked,
              likes: result.likes,
            );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _likedOverride = wasLiked;
          _likesOverride = currentLikes < 0 ? 0 : currentLikes;
        });
      }
      ref
          .read(postLikeUiControllerProvider.notifier)
          .setStateForPost(
            postId: widget.id,
            liked: wasLiked,
            likes: currentLikes < 0 ? 0 : currentLikes,
          );
    } finally {
      if (mounted) setState(() => _likeBusy = false);
    }

    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() => _showHeart = false);
  }

  void _onOverlayToggleLike(bool liked, int likes) {
    final safeLikes = likes < 0 ? 0 : likes;
    setState(() {
      _likedOverride = liked;
      _likesOverride = safeLikes;
    });
    ref
        .read(postLikeUiControllerProvider.notifier)
        .setStateForPost(postId: widget.id, liked: liked, likes: safeLikes);
  }

  @override
  Widget build(BuildContext context) {
    final image = widget.data['imageUrl'] as String?;
    final metadataAspect = _readAspect(widget.data);

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
                  FullscreenBoomerangMedia(
                    controller: _controller,
                    posterUrl: image,
                    showPosterOverlay: _showPosterOverlay,
                    explicitVideoAspectRatio: metadataAspect,
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
                    _userPaused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    color: Colors.white,
                    size: 48.r,
                  ),
                ),
              ),
            ),
          BoomerangOverlay(
            boomerangId: widget.id,
            data: widget.data,
            likedOverride: _likedOverride,
            likesOverride: _likesOverride,
            onToggleLike: _onOverlayToggleLike,
          ),
        ],
      ),
    );
  }

  double? _readAspect(Map<String, dynamic> data) {
    final value = data['videoAspectRatio'];
    if (value is num) {
      final parsed = value.toDouble();
      if (parsed.isFinite && parsed > 0) return parsed;
    }
    return null;
  }
}
