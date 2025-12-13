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
  });
  final String initialId;
  final Map<String, dynamic> initialData;

  @override
  ConsumerState<BoomerangPagerPage> createState() => _BoomerangPagerPageState();
}

class _BoomerangPagerPageState extends ConsumerState<BoomerangPagerPage> {
  final _docs = <({String id, Map<String, dynamic> data})>[];
  bool _loading = false;
  bool _hasMore = true;
  dynamic _last;
  late final PageController _pageController;

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
      final items = snap.docs
          .where((d) => d.id != widget.initialId) // avoid duplicate
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
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            onPageChanged: (i) {
              if (_docs.length - i <= 3) {
                _fetchNext();
              }
            },
            itemCount: _docs.length + (_hasMore ? 1 : 0),
            itemBuilder: (context, i) {
              if (i >= _docs.length) {
                return const Center(child: CircularProgressIndicator());
              }
              final it = _docs[i];
              return _PostPage(id: it.id, data: it.data);
            },
          ),
          Positioned(
            left: 8.w,
            top: MediaQuery.of(context).viewPadding.top + 8.h,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostPage extends ConsumerStatefulWidget {
  const _PostPage({required this.id, required this.data});
  final String id;
  final Map<String, dynamic> data;
  @override
  ConsumerState<_PostPage> createState() => _PostPageState();
}

class _PostPageState extends ConsumerState<_PostPage> {
  VideoPlayerController? _controller;
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
        });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _like() async {
    final me = ref.read(currentUserProfileProvider).value;
    if (me == null) return;
    await ref.read(boomerangRepoProvider).toggleLike(
          boomerangId: widget.id,
          userId: me.uid,
          actorName: me.nickname.isNotEmpty ? me.nickname : me.fullName,
          actorAvatar: me.avatarUrl,
        );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final handle =
        '@${(data['userName'] ?? 'user').toString().replaceAll(' ', '_').toLowerCase()}';
    final avatar = data['userAvatar'] as String?;
    final image = data['imageUrl'] as String?;
    final likes = (data['likes'] ?? 0) as int;
    final me = ref.watch(currentUserProfileProvider).value;
    final likedBy =
        (data['likedBy'] as List?)?.cast<String>() ?? const <String>[];
    final isLiked = me != null && likedBy.contains(me.uid);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onDoubleTap: _like,
            behavior: HitTestBehavior.opaque,
            child: _controller != null && _controller!.value.isInitialized
                ? FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: _controller!.value.size.width,
                      height: _controller!.value.size.height,
                      child: VideoPlayer(_controller!),
                    ),
                  )
                : (image != null && image.isNotEmpty
                    ? Image.network(image, fit: BoxFit.cover)
                    : Container(color: Colors.black)),
          ),
        ),
        Positioned(
          left: 12.w,
          bottom: 20.h,
          right: 88.w,
          child: Row(
            children: [
              CircleAvatar(
                radius: 14.r,
                backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                onBackgroundImageError: avatar != null ? (_, __) {} : null,
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  handle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.sp,
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: 12.w,
          bottom: 20.h,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: _like,
                customBorder: const CircleBorder(),
                child: Icon(
                  isLiked ? Icons.favorite : Icons.favorite_border,
                  color: isLiked ? Colors.red : Colors.white,
                  size: 30.r,
                ),
              ),
              SizedBox(height: 12.h),
              Text(
                '$likes',
                style: TextStyle(color: Colors.white, fontSize: 12.sp),
              ),
            ],
          ),
        ),
      ],
    );
  }
}


