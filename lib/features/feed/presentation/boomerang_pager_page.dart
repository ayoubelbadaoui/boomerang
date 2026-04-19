import 'package:boomerang/core/utils/color_opacity.dart';
import 'package:boomerang/core/widgets/boomerang_overlay.dart';
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
  });
  final String initialId;
  final Map<String, dynamic> initialData;
  final String? targetCommentId;
  final String? targetReplyId;

  @override
  ConsumerState<BoomerangPagerPage> createState() => _BoomerangPagerPageState();
}

class _BoomerangPagerPageState extends ConsumerState<BoomerangPagerPage> {
  final _docs = <({String id, Map<String, dynamic> data})>[];
  bool _loading = false;
  bool _hasMore = true;
  dynamic _last;
  late final PageController _pageController;
  int _currentPage = 0;

  bool _initialPostBlocked = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _docs.add((id: widget.initialId, data: widget.initialData));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialPostPrivacy();
      _fetchNext();
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
  }

  void _checkInitialPostPrivacy() {
    final data = widget.initialData;
    final ownerIsPrivate = data['ownerIsPrivate'] == true;
    if (!ownerIsPrivate) return;
    final me = ref.read(currentUserProfileProvider).value;
    final ownerId = (data['userId'] ?? '') as String;
    if (me?.uid == ownerId) return;
    final followingIds = ref.read(followingIdsProvider).value ?? const <String>{};
    if (followingIds.contains(ownerId)) return;
    setState(() => _initialPostBlocked = true);
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

  Future<void> _fetchNext() async {
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
              .where((d) =>
                  d.id != widget.initialId &&
                  !blockedSet.contains((d.data()['userId'] ?? '') as String))
              .map((d) => (id: d.id, data: d.data()))
              .toList();
      setState(() {
        _docs.addAll(items);
        if (snap.docs.isNotEmpty) _last = snap.docs.last;
        if (snap.docs.length < 10) _hasMore = false;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initialPostBlocked) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            onPressed: () => Navigator.pop(context),
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        onPageChanged: (i) {
          setState(() => _currentPage = i);
          if (_docs.length - i <= 3) _fetchNext();
        },
        itemCount: _docs.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _docs.length) {
            return const Center(child: CircularProgressIndicator());
          }
          final it = _docs[i];
          return _PostPage(
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
      _controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl))
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

  @override
  void initState() {
    super.initState();
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
    if (uid == null) return;
    final likedBy = (widget.data['likedBy'] as List?)?.cast<String>() ??
        const <String>[];
    final wasLiked = _likedOverride ?? likedBy.contains(uid);
    final currentLikes =
        _likesOverride ?? (widget.data['likes'] ?? 0) as int;

    if (!wasLiked) {
      setState(() {
        _likedOverride = true;
        _likesOverride = currentLikes + 1;
      });
    }

    setState(() => _showHeart = true);
    _anim.forward(from: 0);

    final me = ref.read(currentUserProfileProvider).value;
    await ref.read(boomerangRepoProvider).toggleLike(
          boomerangId: widget.id,
          userId: uid,
          actorName: me != null
              ? (me.nickname.isNotEmpty ? me.nickname : me.fullName)
              : 'User',
          actorAvatar: me?.avatarUrl,
        );

    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() => _showHeart = false);
  }

  void _onOverlayToggleLike(bool liked, int likes) {
    setState(() {
      _likedOverride = liked;
      _likesOverride = likes;
    });
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (widget.controller != null &&
                    widget.controller!.value.isInitialized)
                  FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: widget.controller!.value.size.width,
                      height: widget.controller!.value.size.height,
                      child: VideoPlayer(widget.controller!),
                    ),
                  )
                else
                  Container(color: Colors.black),
                if (widget.image != null &&
                    widget.image!.isNotEmpty &&
                    widget.showPosterOverlay)
                  AnimatedOpacity(
                    opacity: widget.showPosterOverlay ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: Image.network(
                      widget.image!,
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
}
