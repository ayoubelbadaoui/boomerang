import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';
import 'package:boomerang/features/feed/presentation/sheets/profile_preview_sheet.dart';

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
      final items =
          snap.docs
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
  bool _showPosterOverlay = true;
  bool? _liked;
  int? _likes;
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
        });
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
    final readyToReveal =
        !v.isBuffering && (v.isPlaying || v.position > Duration.zero);
    if (readyToReveal && _showPosterOverlay) {
      setState(() => _showPosterOverlay = false);
      c.removeListener(_onVideoTickForPoster);
    }
  }

  Future<void> _like() async {
    final me = ref.read(currentUserProfileProvider).value;
    if (me == null) return;
    final baseLikedIds =
        ref.read(likedPostIdsProvider).maybeWhen(data: (ids) => ids, orElse: () => <String>{});
    final baseIsLiked = _liked ?? baseLikedIds.contains(widget.id);
    final nextLiked = !baseIsLiked;
    final currentLikes = _likes ?? (widget.data['likes'] ?? 0) as int;
    final nextLikes = currentLikes + (nextLiked ? 1 : -1);
    debugPrint('pager like tap post=${widget.id} nextLiked=$nextLiked');
    setState(() {
      _liked = nextLiked;
      _likes = nextLikes;
    });
    await ref
        .read(boomerangRepoProvider)
        .toggleLike(
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
    final userId = (data['userId'] ?? '') as String;
    final likes = _likes ?? (data['likes'] ?? 0) as int;
    final me = ref.read(currentUserProfileProvider).value;
    final likedBy =
        (data['likedBy'] as List?)?.cast<String>() ?? const <String>[];
    final likedIds =
        ref.watch(likedPostIdsProvider).value ?? const <String>{};
    final isLiked = _liked ??
        likedIds.contains(widget.id) ||
        (me != null && likedBy.contains(me.uid));

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onDoubleTap: _like,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_controller != null && _controller!.value.isInitialized)
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
                  // Keep background non-black if we have no poster
                  Container(color: Colors.black),
                if (image != null && image.isNotEmpty && _showPosterOverlay)
                  AnimatedOpacity(
                    opacity: _showPosterOverlay ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: Image.network(image, fit: BoxFit.cover),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 12.w,
          bottom: 20.h,
          right: 88.w,
          child: Row(
            children: [
              InkWell(
                onTap:
                    () => _showProfilePreview(context, handle, avatar, userId),
                customBorder: const CircleBorder(),
                child: CircleAvatar(
                  radius: 14.r,
                  backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                  onBackgroundImageError: avatar != null ? (_, __) {} : null,
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: InkWell(
                  onTap:
                      () =>
                          _showProfilePreview(context, handle, avatar, userId),
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
              _ActionCircle(
                icon: Icons.chat_bubble_rounded,
                onTap: () => _showCommentsSheet(context, widget.id),
              ),
              SizedBox(height: 12.h),
              if (me != null)
                Builder(
                  builder: (context) {
                    final uid = me.uid;
                    return StreamBuilder<bool>(
                      stream: ref
                          .watch(savedRepoProvider)
                          .watchIsSaved(userId: uid, boomerangId: widget.id),
                      initialData: false,
                      builder: (context, snapshot) {
                        final saved = snapshot.data ?? false;
                        return InkWell(
                          onTap: () async {
                            await ref
                                .read(savedRepoProvider)
                                .toggleSave(
                                  userId: uid,
                                  boomerangId: widget.id,
                                  boomerangData: widget.data,
                                );
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    saved
                                        ? 'Removed from saved'
                                        : 'Saved to your profile',
                                  ),
                                ),
                              );
                            }
                          },
                          customBorder: const CircleBorder(),
                          child: Icon(
                            saved ? Icons.bookmark : Icons.bookmark_outline,
                            color: Colors.white,
                            size: 26.r,
                          ),
                        );
                      },
                    );
                  },
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

class _ActionCircle extends StatelessWidget {
  const _ActionCircle({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        padding: EdgeInsets.all(10.r),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}

void _showProfilePreview(
  BuildContext context,
  String handle,
  String? avatar,
  String userId,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder:
        (_) => ProfilePreviewSheet(
          userId: userId,
          handle: handle,
          avatarUrl: avatar,
          subtitle: '',
        ),
  );
}

void _showCommentsSheet(BuildContext context, String boomerangId) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.98,
        minChildSize: 0.5,
        builder: (context, controller) {
          return _CommentsSheet(
            boomerangId: boomerangId,
            scrollController: controller,
          );
        },
      );
    },
  );
}

class _CommentsSheet extends ConsumerStatefulWidget {
  const _CommentsSheet({
    required this.boomerangId,
    required this.scrollController,
  });
  final String boomerangId;
  final ScrollController scrollController;

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stream = ref.watch(commentsRepoProvider).watch(widget.boomerangId);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        children: [
          SizedBox(height: 8.h),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Comments',
                style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder(
              stream: stream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                return ListView.builder(
                  primary: false,
                  controller: widget.scrollController,
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final c = docs[i].data();
                    final userName = (c['userName'] ?? 'User') as String;
                    final userAvatar = c['userAvatar'] as String?;
                    final text = (c['text'] ?? '') as String;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage:
                            userAvatar != null
                                ? NetworkImage(userAvatar)
                                : null,
                      ),
                      title: Text(
                        userName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(text),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _text,
                    decoration: InputDecoration(
                      hintText: 'Add comment...',
                      filled: true,
                      fillColor: const Color(0xFFF6F6F6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24.r),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16.w,
                        vertical: 14.h,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                InkWell(
                  onTap: () async {
                    final text = _text.text.trim();
                    if (text.isEmpty) return;
                    final user = ref.read(currentUserProfileProvider).value;
                    _text.clear();
                    FocusScope.of(context).unfocus();
                    await ref
                        .read(commentsRepoProvider)
                        .add(
                          boomerangId: widget.boomerangId,
                          userId: user?.uid ?? 'anon',
                          userName:
                              user?.nickname.isNotEmpty == true
                                  ? user!.nickname
                                  : (user?.fullName ?? 'User'),
                          userAvatar: user?.avatarUrl,
                          text: text,
                        );
                  },
                  child: CircleAvatar(
                    radius: 24.r,
                    backgroundColor: Colors.black,
                    child: const Icon(Icons.send, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
