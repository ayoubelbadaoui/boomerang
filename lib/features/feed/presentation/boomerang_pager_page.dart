import 'package:boomerang/core/utils/color_opacity.dart';
import 'package:boomerang/core/widgets/boomerang_overlay.dart';
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

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _docs.add((id: widget.initialId, data: widget.initialData));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchNext();
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
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
      final items =
          snap.docs
              .where((d) => d.id != widget.initialId)
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

  void _onVideoTickForPoster() {
    final c = _controller;
    if (c == null) return;
    final v = c.value;
    if (!v.isInitialized) return;
    if (!v.isBuffering && (v.isPlaying || v.position > Duration.zero)) {
      if (_showPosterOverlay) {
        setState(() => _showPosterOverlay = false);
        c.removeListener(_onVideoTickForPoster);
      }
    }
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
  late final AnimationController _anim;

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

  void _onDoubleTap() async {
    setState(() => _showHeart = true);
    _anim.forward(from: 0);
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid != null) {
      final me = ref.read(currentUserProfileProvider).value;
      await ref.read(boomerangRepoProvider).toggleLike(
            boomerangId: widget.id,
            userId: uid,
            actorName: me != null
                ? (me.nickname.isNotEmpty ? me.nickname : me.fullName)
                : 'User',
            actorAvatar: me?.avatarUrl,
          );
    }
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() => _showHeart = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
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
        BoomerangOverlay(
          boomerangId: widget.id,
          data: widget.data,
          showTopBar: true,
        ),
      ],
    );
  }
}
