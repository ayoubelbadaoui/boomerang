import 'package:boomerang/core/utils/color_opacity.dart';
import 'package:boomerang/core/utils/immersive_system_ui.dart';
import 'package:boomerang/core/video/boomerang_video_cache.dart';
import 'package:boomerang/core/widgets/boomerang_overlay.dart';
import 'package:boomerang/features/feed/presentation/widgets/fullscreen_boomerang_media.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';

typedef LoadMoreCallback = Future<void> Function();

class ProfileReelsPage extends ConsumerStatefulWidget {
  const ProfileReelsPage({
    super.key,
    required this.initialItems,
    required this.initialIndex,
    this.hasMore = false,
    this.onLoadMore,
  });

  final List<({String id, Map<String, dynamic> data})> initialItems;
  final int initialIndex;
  final bool hasMore;
  final LoadMoreCallback? onLoadMore;

  @override
  ConsumerState<ProfileReelsPage> createState() => _ProfileReelsPageState();
}

class _ProfileReelsPageState extends ConsumerState<ProfileReelsPage> {
  late final PageController _pageController;
  late int _currentPage;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    ImmersiveSystemUi.enter();
  }

  @override
  void dispose() {
    ImmersiveSystemUi.leave();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _maybeLoadMore(int index) async {
    if (_loadingMore) return;
    if (widget.onLoadMore == null || !widget.hasMore) return;
    if (widget.initialItems.length - index > 3) return;
    _loadingMore = true;
    try {
      await widget.onLoadMore!();
    } finally {
      _loadingMore = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.initialItems;
    final showTrailingLoader = widget.hasMore && widget.onLoadMore != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        onPageChanged: (i) {
          setState(() => _currentPage = i);
          _maybeLoadMore(i);
        },
        itemCount: items.length + (showTrailingLoader ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= items.length) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          final it = items[i];
          return _PostPage(
            key: ValueKey(it.id),
            id: it.id,
            data: it.data,
            isActive: i == _currentPage,
          );
        },
      ),
    );
  }
}

class _PostPage extends ConsumerStatefulWidget {
  const _PostPage({
    super.key,
    required this.id,
    required this.data,
    required this.isActive,
  });
  final String id;
  final Map<String, dynamic> data;
  final bool isActive;

  @override
  ConsumerState<_PostPage> createState() => _PostPageState();
}

class _PostPageState extends ConsumerState<_PostPage> {
  VideoPlayerController? _controller;
  bool _showPosterOverlay = true;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    final videoUrl = widget.data['videoUrl'] as String?;
    if (videoUrl != null && videoUrl.isNotEmpty) {
      // ignore: discarded_futures
      BoomerangVideoCache.instance.createController(videoUrl).then((c) {
        if (!mounted) {
          c.dispose();
          return;
        }
        _controller = c
          ..initialize().then((_) {
            if (!mounted) return;
            _initialized = true;
            setState(() {});
            _controller?.setLooping(true);
            _controller?.setVolume(0.0);
            if (widget.isActive) _controller?.play();
            _controller?.addListener(_onVideoTickForPoster);
            _schedulePosterFallback();
          });
      });
    }
  }

  @override
  void didUpdateWidget(covariant _PostPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive && _initialized) {
      if (widget.isActive) {
        _controller?.play();
      } else {
        _controller?.pause();
      }
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoTickForPoster);
    _controller?.dispose();
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

  /// For very short looping videos the listener may never trigger because
  /// position resets to zero between cycles. Force-clear after a short delay.
  void _schedulePosterFallback() {
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      if (_controller?.value.isInitialized == true) _dismissPoster();
    });
  }

  @override
  Widget build(BuildContext context) {
    return _PostPageWithTicker(
      id: widget.id,
      data: widget.data,
      controller: _controller,
      showPosterOverlay: _showPosterOverlay,
      image: widget.data['imageUrl'] as String?,
    );
  }
}

class _PostPageWithTicker extends ConsumerStatefulWidget {
  const _PostPageWithTicker({
    required this.id,
    required this.data,
    required this.controller,
    required this.showPosterOverlay,
    required this.image,
  });
  final String id;
  final Map<String, dynamic> data;
  final VideoPlayerController? controller;
  final bool showPosterOverlay;
  final String? image;

  @override
  ConsumerState<_PostPageWithTicker> createState() =>
      _PostPageWithTickerState();
}

class _PostPageWithTickerState extends ConsumerState<_PostPageWithTicker>
    with SingleTickerProviderStateMixin {
  bool _showHeart = false;
  bool _userPaused = false;
  bool _showPauseIcon = false;
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
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _onTap() {
    final c = widget.controller;
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
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: _onTap,
            onDoubleTap: _onDoubleTap,
            behavior: HitTestBehavior.opaque,
            child: FullscreenBoomerangMedia(
              controller: widget.controller,
              posterUrl: widget.image,
              showPosterOverlay: widget.showPosterOverlay,
              explicitVideoAspectRatio: _readAspect(widget.data),
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
        BoomerangOverlay(
          boomerangId: widget.id,
          data: widget.data,
          showTopBar: true,
          likedOverride: _likedOverride,
          likesOverride: _likesOverride,
          onToggleLike: _onOverlayToggleLike,
        ),
      ],
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
