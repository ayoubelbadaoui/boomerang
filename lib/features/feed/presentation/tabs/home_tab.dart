import 'dart:async';
import 'package:boomerang/core/widgets/live_avatar.dart';
import 'package:boomerang/core/utils/color_opacity.dart';
import 'package:boomerang/features/moderation/application/moderation_providers.dart';
import 'package:boomerang/features/moderation/presentation/widgets/report_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boomerang/features/feed/presentation/sheets/profile_preview_sheet.dart';
import 'package:boomerang/features/feed/presentation/boomerang_pager_page.dart';
import 'package:boomerang/features/profile/domain/user_profile.dart';
import 'package:boomerang/features/feed/presentation/widgets/comments_sheet.dart';

class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  static const String routeName = '/home_tab';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const _PaginatedBoomerangList();
  }
}

class _PaginatedBoomerangList extends ConsumerStatefulWidget {
  const _PaginatedBoomerangList();
  @override
  ConsumerState<_PaginatedBoomerangList> createState() =>
      _PaginatedBoomerangListState();
}

class _PaginatedBoomerangListState
    extends ConsumerState<_PaginatedBoomerangList> {
  final _controller = ScrollController();
  final _docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  final _localLiked = <String, bool>{};
  final _localLikeCounts = <String, int>{};
  DocumentSnapshot<Map<String, dynamic>>? _last;
  bool _loading = false;
  bool _hasMore = true;
  bool _refreshing = false;
  bool _initialFollowingLoaded = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final threshold = 300.0;
    if (_controller.position.maxScrollExtent - _controller.position.pixels <=
        threshold) {
      _fetchNext();
    }
  }

  Future<void> _fetchNext() async {
    if (_loading || !_hasMore) return;
    final me = ref.read(currentUserProfileProvider).value;
    final followingIds = ref.read(followingIdsProvider).value;
    if (me == null || followingIds == null) return;

    setState(() => _loading = true);
    try {
      final docs = await ref
          .read(boomerangRepoProvider)
          .fetchFollowingFeedPage(
            followingIds: followingIds,
            myUid: me.uid,
            startAfter: _last,
            limit: 20,
          );
      if (mounted) {
        setState(() {
          _docs.addAll(docs);
          if (docs.isNotEmpty) {
            _last = docs.last;
          }
          if (docs.length < 20) {
            _hasMore = false;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _docs.clear();
      _last = null;
      _hasMore = true;
    });
    await _fetchNext();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final likedIds = ref.watch(likedPostIdsProvider).value ?? const <String>{};
    final blockedSet =
        ref.watch(blockedUsersProvider).value?.toSet() ?? const <String>{};
    final followingAsync = ref.watch(followingIdsProvider);

    // Trigger initial fetch once following list resolves
    if (!_initialFollowingLoaded && followingAsync.hasValue) {
      _initialFollowingLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchNext());
    }

    // Still waiting for following list
    if (!followingAsync.hasValue && _docs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final me = ref.watch(currentUserProfileProvider).value;
    final meUid = me?.uid ?? '';
    final currentFollowingIds = followingAsync.value ?? const <String>{};
    final visibleDocs = _docs.where((d) {
      final data = d.data();
      final uid = (data['userId'] ?? '') as String;
      if (blockedSet.contains(uid)) return false;
      if (data['ownerIsPrivate'] == true &&
          !currentFollowingIds.contains(uid) &&
          uid != meUid) {
        return false;
      }
      return true;
    }).toList();
    final isLoadingInitial = visibleDocs.isEmpty && _loading && !_refreshing;

    return RefreshIndicator(
      color: Colors.black,
      onRefresh: _refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        primary: false,
        controller: _controller,
        addAutomaticKeepAlives: false,
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 100.h),
        itemCount:
            isLoadingInitial
                ? 1
                : (visibleDocs.length +
                    (_hasMore ? 1 : (visibleDocs.isEmpty ? 1 : 0))),
        separatorBuilder: (_, __) => const SizedBox(),
        itemBuilder: (context, i) {
          if (isLoadingInitial) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (visibleDocs.isEmpty) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 60.h),
              child: Column(
                children: [
                  Icon(Icons.people_outline, size: 48.r, color: Colors.black26),
                  SizedBox(height: 12.h),
                  Text(
                    'Follow people to see their boomerangs here',
                    style: TextStyle(
                      fontSize: 15.sp,
                      color: Colors.black45,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          if (i >= visibleDocs.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final d = visibleDocs[i];
          final data = d.data();
          final overrideLiked = _localLiked[d.id];
          final likesOverride = _localLikeCounts[d.id];
          final isLiked = overrideLiked ?? likedIds.contains(d.id);
          return _BoomerangCard(
            key: ValueKey(d.id),
            id: d.id,
            data: data,
            likedOverride: isLiked,
            likesOverride: likesOverride,
            onToggleLike: (liked, likes) {
              setState(() {
                _localLiked[d.id] = liked;
                _localLikeCounts[d.id] = likes;
              });
            },
          );
        },
      ),
    );
  }
}

class _BoomerangCard extends ConsumerWidget {
  const _BoomerangCard({
    super.key,
    required this.id,
    required this.data,
    this.likedOverride,
    this.likesOverride,
    this.onToggleLike,
  });
  final String id;
  final Map<String, dynamic> data;
  final bool? likedOverride;
  final int? likesOverride;
  final void Function(bool liked, int likes)? onToggleLike;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handle =
        '@${(data['userName'] ?? 'user').toString().replaceAll(' ', '_').toLowerCase()}';
    final userId = (data['userId'] ?? '') as String;
    final avatarFallback = data['userAvatar'] as String?;
    final image = data['imageUrl'] as String?; // optional poster
    final video = data['videoUrl'] as String?;
    final likes = (likesOverride ?? data['likes'] ?? 0) as int;
    final me = ref.read(currentUserProfileProvider).value;
    final likedBy =
        (data['likedBy'] as List?)?.cast<String>() ?? const <String>[];
    final isLiked = likedOverride ?? (me != null && likedBy.contains(me.uid));
    debugPrint(
      'card build: $id isLiked=$isLiked source=${likedOverride != null ? 'override' : 'firestore'} likes=$likes',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24.r),
          child: Container(
            color:
                (image != null && image.isNotEmpty)
                    ? Colors.black
                    : const Color(0xFFF2F2F2),
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: 3 / 4,
                  child: _DoubleTapLikeArea(
                    postId: id,
                    data: data,
                    isLiked: isLiked,
                    onToggleLike: (liked) {
                      final nextLikes = liked ? likes + 1 : likes - 1;
                      onToggleLike?.call(liked, nextLikes);
                    },
                    child: _BoomerangMedia(videoUrl: video, posterUrl: image, postId: id),
                  ),
                ),
                Positioned(
                  left: 18.w,
                  top: 16.h,
                  child: Row(
                    children: [
                      InkWell(
                        onTap:
                            () => _showProfilePreview(
                              context,
                              handle,
                              userId,
                            ),
                        customBorder: const CircleBorder(),
                        child: LiveAvatar(userId: userId, fallbackUrl: avatarFallback, size: 36.r),
                      ),
                      SizedBox(width: 10.w),
                      InkWell(
                        onTap:
                            () => _showProfilePreview(
                              context,
                              handle,
                              userId,
                            ),
                        child: Text(
                          handle,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16.sp,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 20.w,
                  top: 18.h,
                  child: _BookmarkButton(postId: id, data: data),
                ),
                Positioned(
                  left: 12.w,
                  bottom: 20.h,
                  child: Row(
                    children: [
                      _CommentButton(
                        boomerangId: id,
                        data: data,
                      ),
                      SizedBox(width: 8.w),
                      _SvgCircleBtn(
                        asset: 'assets/svgs/share.svg',
                        onTap: () =>
                            _showShareSheet(context, data, boomerangId: id),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 18.w,
                  bottom: 24.h,
                  child: _LikeCircleButton(
                    isLiked: isLiked,
                    likes: likes,
                    onToggleLike: (nextLiked, nextLikes) async {
                      final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
                      if (uid == null) return;
                      final me = ref.read(currentUserProfileProvider).value;
                      onToggleLike?.call(nextLiked, nextLikes);
                      final authUser = ref.read(firebaseAuthProvider).currentUser;
                      await ref
                          .read(boomerangRepoProvider)
                          .toggleLike(
                            boomerangId: id,
                            userId: uid,
                            actorName: me != null ? _bestName(me) : (authUser?.displayName ?? 'User'),
                            actorAvatar: me?.avatarUrl ?? authUser?.photoURL,
                          );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      handle,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w700,
                        fontSize: 16.sp,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      (data['caption'] ?? '') as String? ?? '',
                      textAlign: TextAlign.left,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.black87, fontSize: 14.sp),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SvgCircleBtn extends StatelessWidget {
  const _SvgCircleBtn({required this.asset, this.onTap});
  final String asset;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.black,
          shape: BoxShape.circle,
        ),
        padding: EdgeInsets.all(12.r),
        child: SvgPicture.asset(
          asset,
          width: 24.r,
          height: 24.r,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
      ),
    );
  }
}

class _CommentButton extends ConsumerWidget {
  const _CommentButton({required this.boomerangId, required this.data});
  final String boomerangId;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _showCommentsSheet(context, boomerangId, data),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.black,
          shape: BoxShape.circle,
        ),
        padding: EdgeInsets.all(12.r),
        child: SvgPicture.asset(
          'assets/svgs/comment.svg',
          width: 24.r,
          height: 24.r,
          colorFilter:
              const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
      ),
    );
  }
}

class _BookmarkButton extends ConsumerWidget {
  const _BookmarkButton({required this.postId, required this.data});
  final String postId;
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProfileProvider).value;
    if (me == null) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<bool>(
      stream: ref
          .watch(savedRepoProvider)
          .watchIsSaved(userId: me.uid, boomerangId: postId),
      initialData: false,
      builder: (context, snap) {
        final saved = snap.data ?? false;
        return InkWell(
          onTap: () async {
            await ref
                .read(savedRepoProvider)
                .toggleSave(
                  userId: me.uid,
                  boomerangId: postId,
                  boomerangData: data,
                );
          },
          customBorder: const CircleBorder(),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
            ),
            padding: EdgeInsets.all(12.r),
            child: SvgPicture.asset(
              'assets/svgs/Bookmark.svg',
              width: 24.r,
              height: 24.r,
              colorFilter: ColorFilter.mode(
                saved ? Colors.yellow : Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LikeCircleButton extends ConsumerStatefulWidget {
  const _LikeCircleButton({
    required this.isLiked,
    required this.likes,
    required this.onToggleLike,
  });
  final bool isLiked;
  final int likes;
  final Future<void> Function(bool nextLiked, int nextLikes) onToggleLike;

  @override
  ConsumerState<_LikeCircleButton> createState() => _LikeCircleButtonState();
}

class _LikeCircleButtonState extends ConsumerState<_LikeCircleButton> {
  bool _busy = false;

  Future<void> _tap() async {
    if (_busy) return;
    final nextLiked = !widget.isLiked;
    final nextLikes = widget.likes + (nextLiked ? 1 : -1);
    setState(() => _busy = true);
    try {
      await widget.onToggleLike(nextLiked, nextLikes);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _busy ? null : _tap,
      customBorder: const CircleBorder(),
      child: SvgPicture.asset(
        'assets/heart.svg',
        width: 36.w,
        height: 36.w,
        colorFilter: ColorFilter.mode(
          widget.isLiked ? Colors.red : Colors.white,
          BlendMode.srcIn,
        ),
      ),
    );
  }
}

class _DoubleTapLikeArea extends ConsumerStatefulWidget {
  const _DoubleTapLikeArea({
    required this.postId,
    required this.data,
    required this.child,
    required this.isLiked,
    required this.onToggleLike,
  });
  final String postId;
  final Map<String, dynamic> data;
  final Widget child;
  final bool isLiked;
  final void Function(bool liked) onToggleLike;
  @override
  ConsumerState<_DoubleTapLikeArea> createState() => _DoubleTapLikeAreaState();
}

String _bestName(UserProfile profile) {
  if (profile.nickname.trim().isNotEmpty) return profile.nickname;
  if (profile.fullName.trim().isNotEmpty) return profile.fullName;
  return 'User';
}

class _DoubleTapLikeAreaState extends ConsumerState<_DoubleTapLikeArea>
    with SingleTickerProviderStateMixin {
  bool _showHeart = false;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _like() async {
    final me = ref.read(currentUserProfileProvider).value;
    if (me == null) return;
    widget.onToggleLike(!widget.isLiked);
    await ref
        .read(boomerangRepoProvider)
        .toggleLike(
          boomerangId: widget.postId,
          userId: me.uid,
          actorName: _bestName(me),
          actorAvatar: me.avatarUrl,
        );
  }

  void _onDoubleTap() async {
    setState(() => _showHeart = true);
    _controller.forward(from: 0);
    await _like();
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() => _showHeart = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder:
                (_) => BoomerangPagerPage(
                  initialId: widget.postId,
                  initialData: widget.data,
                ),
          ),
        );
      },
      onDoubleTap: _onDoubleTap,
      onLongPress: null,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_showHeart)
            Center(
              child: ScaleTransition(
                scale: Tween(begin: 0.6, end: 1.2).animate(
                  CurvedAnimation(
                    parent: _controller,
                    curve: Curves.easeOutBack,
                  ),
                ),
                child: Icon(
                  Icons.favorite,
                  color: Colors.white.fade(0.9),
                  size: 100.r,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

void _showProfilePreview(
  BuildContext context,
  String handle,
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
        ),
  );
}

void _showShareSheet(
  BuildContext context,
  Map<String, dynamic> data, {
  required String boomerangId,
}) {
  final videoUrl = data['videoUrl'] as String?;
  final shareText = videoUrl ?? 'Check out this Boomerang!';
  final userId = (data['userId'] ?? '') as String;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 24.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                margin: EdgeInsets.only(bottom: 16.h),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              _ShareOption(
                icon: Icons.share_outlined,
                label: 'Share',
                onTap: () {
                  Navigator.pop(context);
                  // ignore: deprecated_member_use
                  Share.share(shareText);
                },
              ),
              _ShareOption(
                icon: Icons.link_rounded,
                label: 'Copy link',
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: shareText));
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  }
                },
              ),
              _ShareOption(
                icon: Icons.download_outlined,
                label: 'Save',
                onTap: () async {
                  if (videoUrl != null && videoUrl.isNotEmpty) {
                    await Clipboard.setData(ClipboardData(text: videoUrl));
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Boomerang link copied')),
                      );
                    }
                  } else {
                    Navigator.pop(context);
                  }
                },
              ),
              _ShareOption(
                icon: Icons.flag_outlined,
                label: 'Report',
                onTap: () {
                  Navigator.pop(context);
                  showReportSheet(
                    context,
                    reportedUid: userId,
                    boomerangId: boomerangId,
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

void _showCommentsSheet(
  BuildContext context,
  String boomerangId,
  Map<String, dynamic> data,
) {
  final postOwnerId = (data['userId'] ?? '') as String;
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
        builder:
            (context, controller) => CommentsSheet(
              boomerangId: boomerangId,
              scrollController: controller,
              postOwnerId: postOwnerId,
            ),
      );
    },
  );
}

class _ShareOption extends StatelessWidget {
  const _ShareOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.r),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 14.h),
        child: Row(
          children: [
            Container(
              width: 44.r,
              height: 44.r,
              decoration: const BoxDecoration(
                color: Color(0xFFF2F2F2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.black, size: 22.r),
            ),
            SizedBox(width: 16.w),
            Text(
              label,
              style: TextStyle(
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BoomerangMedia extends StatefulWidget {
  const _BoomerangMedia({
    required this.videoUrl,
    required this.posterUrl,
    required this.postId,
  });
  final String? videoUrl;
  final String? posterUrl;
  final String postId;

  @override
  State<_BoomerangMedia> createState() => _BoomerangMediaState();
}

class _BoomerangMediaState extends State<_BoomerangMedia> {
  VideoPlayerController? _controller;
  bool _videoReady = false;
  bool _visible = false;
  bool _initialized = false;

  @override
  void didUpdateWidget(covariant _BoomerangMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.videoUrl != oldWidget.videoUrl) {
      _disposeController();
      if (_visible) _initController();
    }
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    final nowVisible = info.visibleFraction >= 0.5;
    if (nowVisible == _visible) return;
    _visible = nowVisible;

    if (_visible) {
      if (!_initialized) {
        _initController();
      } else {
        _controller?.play();
      }
    } else {
      _controller?.pause();
    }
  }

  Future<void> _initController() async {
    final url = widget.videoUrl;
    if (url == null || url.isEmpty) return;
    _videoReady = false;
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      _initialized = true;
      await controller.setLooping(true);
      await controller.setVolume(0.0);
      if (_visible) await controller.play();
      if (mounted) setState(() => _videoReady = true);
    } catch (_) {}
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
    _videoReady = false;
    _initialized = false;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasPoster = widget.posterUrl != null && widget.posterUrl!.isNotEmpty;

    Widget posterLayer() {
      if (hasPoster) {
        final cacheW = (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round();
        return Image.network(
          widget.posterUrl!,
          fit: BoxFit.cover,
          cacheWidth: cacheW,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        );
      }
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFEDEDED), Color(0xFFF7F7F7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Center(
          child: Icon(Icons.play_circle_fill, color: Colors.black38, size: 42),
        ),
      );
    }

    final hasVideo = _controller != null && _controller!.value.isInitialized;

    return VisibilityDetector(
      key: Key('bmg-media-${widget.postId}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedOpacity(
            opacity: _videoReady ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 220),
            child: posterLayer(),
          ),
          if (hasVideo)
            AnimatedOpacity(
              opacity: _videoReady ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 260),
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

