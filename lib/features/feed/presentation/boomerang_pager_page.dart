import 'package:boomerang/core/utils/color_opacity.dart';
import 'package:boomerang/core/widgets/boomerang_overlay.dart';
import 'package:boomerang/core/widgets/boomerang_pager_shimmer.dart';
import 'package:boomerang/features/feed/application/feed_controller.dart';
import 'package:boomerang/features/feed/domain/entities/ranked_post.dart';
import 'package:boomerang/features/feed/domain/ranking/feed_surface.dart';
import 'package:boomerang/features/feed/presentation/widgets/fullscreen_boomerang_media.dart';
import 'package:boomerang/features/moderation/application/moderation_providers.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';

class BoomerangPagerPage extends ConsumerStatefulWidget {
  const BoomerangPagerPage({
    super.key,
    required this.initialId,
    required this.initialData,
    this.targetCommentId,
    this.targetReplyId,
    this.feedSurface,
  });
  final String initialId;
  final Map<String, dynamic> initialData;
  final String? targetCommentId;
  final String? targetReplyId;

  /// When set, subsequent posts are paged from the ranked [FeedController] for
  /// this surface (preserving the feed's ordering) instead of the global
  /// chronological timeline. Used so opening a post from Discovery keeps
  /// scrolling within the Discovery feed.
  final FeedSurface? feedSurface;

  @override
  ConsumerState<BoomerangPagerPage> createState() => _BoomerangPagerPageState();
}

class _BoomerangPagerPageState extends ConsumerState<BoomerangPagerPage> {
  final _docs = <({String id, Map<String, dynamic> data})>[];
  final _likedOverrides = <String, bool>{};
  final _likeCountOverrides = <String, int>{};
  final _seenIds = <String>{};
  bool _loading = false;
  bool _hasMore = true;
  dynamic _last;

  // Absolute index of the next item to consume from the ranked feed surface
  // (only used when [widget.feedSurface] is set).
  int _surfaceNextIndex = 0;
  late final PageController _pageController;
  int _currentPage = 0;
  int _prewarmedUntil = -1;

  // How many upcoming POSTER images to prefetch ahead of the current page.
  // Poster prefetch is cheap (bounded by the image cache) and is what keeps the
  // feed looking smooth — a sharp poster shows instantly while each page's own
  // video controller initializes. (Video prewarming was removed: it span up an
  // ExoPlayer per upcoming item and OOM-crashed the app while scrolling.)
  static const int _initialPrewarmCount = 4;
  static const int _rollingPrewarmBatch = 3;
  static const int _prewarmTriggerRemaining = 2;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _docs.add((id: widget.initialId, data: widget.initialData));
    _seenIds.add(widget.initialId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSurfaceCursor();
      _advancePrewarmWindow(fromIndex: 0, count: _initialPrewarmCount);
      _fetchNext();
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
  }

  bool _isOwnerLockedFromMe(Map<String, dynamic> data) {
    final ownerId = (data['userId'] ?? '') as String;
    if (ownerId.isEmpty) return false;
    final me = ref.watch(currentUserProfileProvider).value;
    if (me?.uid == ownerId) return false;
    final liveProfile = ref.watch(userProfileByIdProvider(ownerId)).value;
    final cached = data['ownerIsPrivate'] == true;
    final isPrivate = (liveProfile?.isPrivate ?? cached) || cached;
    if (!isPrivate) return false;
    final followingIds =
        ref.watch(followingIdsProvider).value ?? const <String>{};
    return !followingIds.contains(ownerId);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    _pageController.dispose();
    super.dispose();
  }

  void _initSurfaceCursor() {
    final surface = widget.feedSurface;
    if (surface == null) return;
    final items =
        ref.read(feedControllerProvider(surface)).value?.items ??
        const <RankedPost>[];
    final idx = items.indexWhere((p) => p.id == widget.initialId);
    // Continue right after the tapped post when found; otherwise start from the
    // top of the loaded feed (the tapped id is already in _seenIds so it won't
    // be duplicated).
    _surfaceNextIndex = idx >= 0 ? idx + 1 : 0;
  }

  Future<void> _fetchNext() async {
    if (widget.feedSurface != null) {
      await _fetchNextFromSurface();
      return;
    }
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final snap = await ref
          .read(boomerangRepoProvider)
          .fetchBoomerangsPage(startAfter: _last, limit: 10);
      final blockedSet =
          ref.read(blockedUsersProvider).value?.toSet() ?? const <String>{};
      final items =
          snap.docs
              .where(
                (d) =>
                    d.id != widget.initialId &&
                    !blockedSet.contains((d.data()['userId'] ?? '') as String),
              )
              .map((d) => (id: d.id, data: d.data()))
              .toList();
      setState(() {
        _docs.addAll(items);
        if (snap.docs.isNotEmpty) _last = snap.docs.last;
        if (snap.docs.length < 10) _hasMore = false;
      });
      _advancePrewarmWindow(
        fromIndex: _currentPage,
        count: _rollingPrewarmBatch,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _fetchNextFromSurface() async {
    if (_loading || !_hasMore) return;
    final surface = widget.feedSurface!;
    setState(() => _loading = true);
    try {
      var feedState = ref.read(feedControllerProvider(surface)).value;
      // Pull another ranked page when we've exhausted what's already loaded.
      if (feedState != null &&
          _surfaceNextIndex >= feedState.items.length &&
          feedState.hasMore) {
        await ref.read(feedControllerProvider(surface).notifier).fetchNext();
        feedState = ref.read(feedControllerProvider(surface)).value;
      }

      final blockedSet =
          ref.read(blockedUsersProvider).value?.toSet() ?? const <String>{};
      final newItems = <({String id, Map<String, dynamic> data})>[];
      if (feedState != null) {
        while (_surfaceNextIndex < feedState.items.length) {
          final post = feedState.items[_surfaceNextIndex];
          _surfaceNextIndex++;
          if (_seenIds.contains(post.id)) continue;
          if (blockedSet.contains(post.authorId)) continue;
          _seenIds.add(post.id);
          newItems.add((id: post.id, data: post.raw));
        }
      }

      final moreAvailable =
          feedState != null &&
          (feedState.hasMore || _surfaceNextIndex < feedState.items.length);

      setState(() {
        _docs.addAll(newItems);
        _hasMore = moreAvailable;
      });
      _advancePrewarmWindow(
        fromIndex: _currentPage,
        count: _rollingPrewarmBatch,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _advancePrewarmWindow({required int fromIndex, required int count}) {
    if (!mounted || _docs.isEmpty) return;
    final safeFrom = fromIndex.clamp(0, _docs.length - 1);
    final target = (safeFrom + count).clamp(0, _docs.length - 1);
    if (target <= _prewarmedUntil) return;
    for (var i = _prewarmedUntil + 1; i <= target; i++) {
      _warmPosterFor(i);
    }
    _prewarmedUntil = target;
  }

  void _warmPosterFor(int index) {
    final poster = _docs[index].data['imageUrl'] as String?;
    if (poster == null || poster.isEmpty) return;
    precacheImage(NetworkImage(poster), context);
  }

  void _ensureRollingPrewarm(int pageIndex) {
    final remainingPrewarmed = _prewarmedUntil - pageIndex;
    if (remainingPrewarmed <= _prewarmTriggerRemaining) {
      _advancePrewarmWindow(fromIndex: pageIndex, count: _rollingPrewarmBatch);
      if (_hasMore &&
          (_docs.length - pageIndex) <= (_rollingPrewarmBatch + 1)) {
        _fetchNext();
      }
    }
  }

  void _onLikeChanged(String postId, bool liked, int likes) {
    final safeLikes = likes < 0 ? 0 : likes;
    ref
        .read(postLikeUiControllerProvider.notifier)
        .setStateForPost(postId: postId, liked: liked, likes: safeLikes);
    if (!mounted) return;
    setState(() {
      _likedOverrides[postId] = liked;
      _likeCountOverrides[postId] = safeLikes;
    });
  }

  Map<String, dynamic> _buildReturnLikeState() {
    final id = widget.initialId;
    final global = resolveActivePostLikeUiState(
      ref.read(postLikeUiEntryProvider(id)),
    );
    final current = _docs.firstWhere(
      (d) => d.id == id,
      orElse: () => (id: id, data: widget.initialData),
    );
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    final fallbackLikedBy =
        (current.data['likedBy'] as List?)?.whereType<String>().toSet() ??
        <String>{};
    final fallbackLiked = uid != null && fallbackLikedBy.contains(uid);
    final fallbackLikes = ((current.data['likes'] ?? 0) as num).toInt();
    return <String, dynamic>{
      'postId': id,
      'liked': _likedOverrides[id] ?? global?.liked ?? fallbackLiked,
      'likes':
          _likeCountOverrides[id] ??
          global?.likes ??
          (fallbackLikes < 0 ? 0 : fallbackLikes),
    };
  }

  void _popWithResult() {
    Navigator.of(context).pop(_buildReturnLikeState());
  }

  @override
  Widget build(BuildContext context) {
    // Always re-evaluate privacy on every build so toggles propagate live.
    if (_docs.isNotEmpty && _isOwnerLockedFromMe(_docs.first.data)) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            onPressed: _popWithResult,
          ),
        ),
        extendBodyBehindAppBar: true,
        body: const Center(
          child: Text(
            'This content is private',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _popWithResult();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          allowImplicitScrolling: true,
          onPageChanged: (i) {
            setState(() => _currentPage = i);
            _ensureRollingPrewarm(i);
            if (_docs.length - i <= 3) _fetchNext();
          },
          itemCount: _docs.length + (_hasMore ? 1 : 0),
          itemBuilder: (context, i) {
            if (i >= _docs.length) {
              return BoomerangPagerShimmer(onBack: _popWithResult);
            }
            final it = _docs[i];
            final globalLike = resolveActivePostLikeUiState(
              ref.watch(postLikeUiEntryProvider(it.id)),
            );
            return _PostPage(
              id: it.id,
              data: it.data,
              isActive: i == _currentPage,
              likedOverride: _likedOverrides[it.id] ?? globalLike?.liked,
              likesOverride: _likeCountOverrides[it.id] ?? globalLike?.likes,
              onLikeChanged:
                  (liked, likes) => _onLikeChanged(it.id, liked, likes),
              onBackPressed: _popWithResult,
            );
          },
        ),
      ),
    );
  }
}

class _PostPage extends ConsumerStatefulWidget {
  const _PostPage({
    required this.id,
    required this.data,
    required this.isActive,
    this.likedOverride,
    this.likesOverride,
    this.onLikeChanged,
    this.onBackPressed,
  });
  final String id;
  final Map<String, dynamic> data;
  final bool isActive;
  final bool? likedOverride;
  final int? likesOverride;
  final void Function(bool liked, int likes)? onLikeChanged;
  final VoidCallback? onBackPressed;
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
      _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl))
        ..initialize()
            .then((_) {
              if (!mounted) return;
              _initialized = true;
              setState(() {});
              _controller?.setLooping(true);
              _controller?.setVolume(0.0);
              if (widget.isActive) _controller?.play();
              _controller?.addListener(_onVideoTickForPoster);
              _schedulePosterFallback();
            })
            .catchError((Object _) {
              if (mounted) setState(() {});
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

  @override
  Widget build(BuildContext context) {
    return _PostPageWithTicker(
      id: widget.id,
      data: widget.data,
      controller: _controller,
      showPosterOverlay: _showPosterOverlay,
      image: widget.data['imageUrl'] as String?,
      initialLikedOverride: widget.likedOverride,
      initialLikesOverride: widget.likesOverride,
      onLikeChanged: widget.onLikeChanged,
      onBackPressed: widget.onBackPressed,
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
    this.initialLikedOverride,
    this.initialLikesOverride,
    this.onLikeChanged,
    this.onBackPressed,
  });
  final String id;
  final Map<String, dynamic> data;
  final VideoPlayerController? controller;
  final bool showPosterOverlay;
  final String? image;
  final bool? initialLikedOverride;
  final int? initialLikesOverride;
  final void Function(bool liked, int likes)? onLikeChanged;
  final VoidCallback? onBackPressed;

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
  bool _posterResolved = false;

  @override
  void initState() {
    super.initState();
    _posterResolved = widget.image == null || widget.image!.isEmpty;
    _primePosterResolution();
    _likedOverride = widget.initialLikedOverride;
    _likesOverride = widget.initialLikesOverride;
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void didUpdateWidget(covariant _PostPageWithTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image) {
      _posterResolved = widget.image == null || widget.image!.isEmpty;
      _primePosterResolution();
    }
    if (widget.initialLikedOverride != oldWidget.initialLikedOverride) {
      _likedOverride = widget.initialLikedOverride;
    }
    if (widget.initialLikesOverride != oldWidget.initialLikesOverride) {
      _likesOverride = widget.initialLikesOverride;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _primePosterResolution() async {
    final image = widget.image;
    if (image == null || image.isEmpty || _posterResolved) return;
    try {
      await precacheImage(NetworkImage(image), context);
    } catch (_) {
      // Treat load failures as resolved so UI does not block.
    } finally {
      if (!mounted || _posterResolved) return;
      setState(() => _posterResolved = true);
    }
  }

  bool _isPagerMediaReady() {
    final videoUrl = widget.data['videoUrl'] as String?;
    final hasVideo = videoUrl != null && videoUrl.isNotEmpty;
    final hasPoster = widget.image != null && widget.image!.isNotEmpty;
    final c = widget.controller;

    if (!hasVideo) {
      return !hasPoster || _posterResolved;
    }

    if (c != null && c.value.hasError) {
      return !hasPoster || _posterResolved;
    }

    final videoOk = c?.value.isInitialized ?? false;
    if (hasPoster) {
      // Show the poster as soon as it resolves; let video catch up in background.
      return _posterResolved;
    }
    return videoOk;
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
      widget.onLikeChanged?.call(true, currentLikes + 1);
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
        widget.onLikeChanged?.call(result.liked, result.likes);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _likedOverride = wasLiked;
          _likesOverride = currentLikes < 0 ? 0 : currentLikes;
        });
      }
      widget.onLikeChanged?.call(wasLiked, currentLikes < 0 ? 0 : currentLikes);
    } finally {
      if (mounted) setState(() => _likeBusy = false);
    }

    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() => _showHeart = false);
  }

  void _onOverlayToggleLike(bool liked, int likes) {
    setState(() {
      _likedOverride = liked;
      _likesOverride = likes;
    });
    widget.onLikeChanged?.call(liked, likes);
  }

  @override
  Widget build(BuildContext context) {
    final mediaReady = _isPagerMediaReady();

    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedOpacity(
            opacity: mediaReady ? 1 : 0,
            duration: const Duration(milliseconds: 260),
            child: GestureDetector(
              onTap: _onTap,
              onDoubleTap: _onDoubleTap,
              behavior: HitTestBehavior.opaque,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color:
                        (widget.image != null && widget.image!.isNotEmpty)
                            ? const Color(0xFF1A1A1A)
                            : Colors.black,
                  ),
                  FullscreenBoomerangMedia(
                    controller: widget.controller,
                    posterUrl: widget.image,
                    showPosterOverlay: widget.showPosterOverlay,
                    explicitVideoAspectRatio: _readAspect(widget.data),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!mediaReady)
          Positioned.fill(
            child: BoomerangPagerShimmer(
              onBack: () => Navigator.of(context).pop(),
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
        AnimatedOpacity(
          opacity: mediaReady ? 1 : 0,
          duration: const Duration(milliseconds: 260),
          child: IgnorePointer(
            ignoring: !mediaReady,
            child: BoomerangOverlay(
              boomerangId: widget.id,
              data: widget.data,
              showTopBar: true,
              onBackPressed: widget.onBackPressed,
              likedOverride: _likedOverride,
              likesOverride: _likesOverride,
              onToggleLike: _onOverlayToggleLike,
            ),
          ),
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
