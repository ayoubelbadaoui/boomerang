import 'dart:async';
import 'package:boomerang/core/utils/color_opacity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boomerang/features/feed/presentation/sheets/profile_preview_sheet.dart';
import 'package:boomerang/features/feed/presentation/sheets/viewers_sheet.dart';
// import 'package:boomerang/features/feed/presentation/boomerang_viewer_page.dart';
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

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _fetchNext();
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
    setState(() => _loading = true);
    try {
      final snap = await ref
          .read(boomerangRepoProvider)
          .fetchBoomerangsPage(startAfter: _last, limit: 20);
      debugPrint(
        'feed: fetched page ${snap.docs.length} (hasMore=${snap.docs.length == 20})',
      );
      if (mounted) {
        setState(() {
          _docs.addAll(snap.docs);
          if (snap.docs.isNotEmpty) {
            _last = snap.docs.last;
          }
          if (snap.docs.length < 20) {
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
      _docs.clear();
      _last = null;
      _hasMore = true;
    });
    debugPrint('feed: refresh triggered');
    await _fetchNext();
  }

  @override
  Widget build(BuildContext context) {
    final likedIds = ref.watch(likedPostIdsProvider).value ?? const <String>{};
    final isLoadingInitial = _docs.isEmpty && _loading;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        primary: false,
        controller: _controller,
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 100.h),
        itemCount:
            isLoadingInitial
                ? 1
                : (_docs.length + (_hasMore ? 1 : (_docs.isEmpty ? 1 : 0))),
        separatorBuilder: (_, __) => SizedBox(height: 16.h),
        itemBuilder: (context, i) {
          if (isLoadingInitial) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (_docs.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('No boomerangs yet')),
            );
          }
          if (i >= _docs.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final d = _docs[i];
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
    final avatar = data['userAvatar'] as String?;
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
                    child: _BoomerangMedia(videoUrl: video, posterUrl: image),
                  ),
                ),
                Positioned(
                  left: 12.w,
                  top: 12.h,
                  child: Row(
                    children: [
                      InkWell(
                        onTap:
                            () => _showProfilePreview(
                              context,
                              handle,
                              avatar,
                              data['userId'] as String,
                            ),
                        customBorder: const CircleBorder(),
                        child: CircleAvatar(
                          radius: 14.r,
                          backgroundImage:
                              avatar != null
                                  ? ResizeImage.resizeIfNeeded(
                                    (28.r *
                                            MediaQuery.of(
                                              context,
                                            ).devicePixelRatio)
                                        .round(),
                                    (28.r *
                                            MediaQuery.of(
                                              context,
                                            ).devicePixelRatio)
                                        .round(),
                                    NetworkImage(avatar),
                                  )
                                  : null,
                          onBackgroundImageError:
                              avatar != null ? (_, __) {} : null,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      InkWell(
                        onTap:
                            () => _showProfilePreview(
                              context,
                              handle,
                              avatar,
                              data['userId'] as String,
                            ),
                        child: Text(
                          handle,
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
                  top: 12.h,
                  child: _BookmarkButton(postId: id, data: data),
                ),
                Positioned(
                  left: 12.w,
                  bottom: 12.h,
                  child: Row(
                    children: [
                      _SvgCircleBtn(
                        asset: 'assets/svgs/comment.svg',
                        onTap: () => _showCommentsSheet(context, id, data),
                      ),
                      SizedBox(width: 8.w),
                      _SvgCircleBtn(
                        asset: 'assets/svgs/share.svg',
                        onTap: () => _showShareSheet(context, data),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      handle,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w700,
                        fontSize: 14.sp,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      (data['caption'] ?? '') as String? ?? '',
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.black87, fontSize: 13.sp),
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
        padding: EdgeInsets.all(10.r),
        child: SvgPicture.asset(
          asset,
          width: 20.r,
          height: 20.r,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
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
            padding: EdgeInsets.all(10.r),
            child: SvgPicture.asset(
              'assets/svgs/Bookmark.svg',
              width: 20.r,
              height: 20.r,
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
  if (profile.username.trim().isNotEmpty) return profile.username;
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
      onLongPress: () => _showViewersSheet(context),
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
          subtitle: 'Dancer & Singer',
        ),
  );
}

void _showViewersSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const ViewersSheet(),
  );
}

void _showShareSheet(BuildContext context, Map<String, dynamic> data) {
  final videoUrl = data['videoUrl'] as String?;
  final handle =
      '@${(data['userName'] ?? 'user').toString().replaceAll(' ', '_').toLowerCase()}';
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  margin: EdgeInsets.only(bottom: 12.h),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Text(
                'Send to',
                style: TextStyle(fontSize: 24.sp, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 12.h),
              const Divider(),
              SizedBox(height: 12.h),
              _QuickRow(handle: handle, videoUrl: videoUrl),
              SizedBox(height: 16.h),
              _ShareGrid(videoUrl: videoUrl),
              SizedBox(height: 12.h),
              const Divider(),
              SizedBox(height: 12.h),
              _SecondaryGrid(videoUrl: videoUrl),
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
            ),
      );
    },
  );
}

class _QuickRow extends StatelessWidget {
  const _QuickRow({required this.handle, required this.videoUrl});
  final String handle;
  final String? videoUrl;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _QuickItem(
          icon: Icons.upload_rounded,
          label: 'Repost',
          // ignore: deprecated_member_use
          onTap: () => Share.share(videoUrl ?? handle),
        ),
        _QuickItem(
          avatar: const CircleAvatar(
            backgroundImage: AssetImage('assets/logo.png'),
          ),
          label: handle.length > 10 ? '${handle.substring(0, 10)}…' : handle,
          // ignore: deprecated_member_use
          onTap: () => Share.share(videoUrl ?? handle),
        ),
        _QuickItem(
          icon: Icons.search,
          label: 'Search',
          onTap: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

class _QuickItem extends StatelessWidget {
  const _QuickItem({
    this.icon,
    this.avatar,
    required this.label,
    required this.onTap,
  });
  final IconData? icon;
  final Widget? avatar;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            height: 64.r,
            width: 64.r,
            decoration: BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
            ),
            child: Center(child: avatar ?? Icon(icon, color: Colors.white)),
          ),
        ),
        SizedBox(height: 6.h),
        Text(label, style: TextStyle(fontSize: 12.sp)),
      ],
    );
  }
}

class _ShareGrid extends StatelessWidget {
  const _ShareGrid({required this.videoUrl});
  final String? videoUrl;
  @override
  Widget build(BuildContext context) {
    final items = [
      _ShareItem('WhatsApp', Icons.chat),
      _ShareItem('Twitter', Icons.alternate_email),
      _ShareItem('Facebook', Icons.facebook),
      _ShareItem('Instagram', Icons.camera_alt_outlined),
      _ShareItem('Yahoo', Icons.mail_outline),
      _ShareItem('Chat', Icons.chat_bubble_outline),
      _ShareItem('WeChat', Icons.wechat),
      _ShareItem('Slack', Icons.message_outlined),
    ];
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 12.h,
        crossAxisSpacing: 12.w,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (context, i) {
        final it = items[i];
        return Column(
          children: [
            InkWell(
              // ignore: deprecated_member_use
              onTap: () => Share.share(videoUrl ?? 'Check this!'),
              customBorder: const CircleBorder(),
              child: CircleAvatar(radius: 28.r, child: Icon(it.icon)),
            ),
            SizedBox(height: 6.h),
            Text(it.label, style: TextStyle(fontSize: 12.sp)),
          ],
        );
      },
    );
  }
}

class _SecondaryGrid extends StatelessWidget {
  const _SecondaryGrid({required this.videoUrl});
  final String? videoUrl;
  @override
  Widget build(BuildContext context) {
    final items = [
      _ShareItem('Report', Icons.flag_outlined),
      _ShareItem('Not Intere..', Icons.favorite_border),
      _ShareItem('Save Vid..', Icons.download_outlined),
      _ShareItem('Set as W..', Icons.video_stable_outlined),
      _ShareItem('Duet', Icons.group_outlined),
      _ShareItem('Stitch', Icons.content_cut),
      _ShareItem('Add to Fa..', Icons.bookmark_border),
      _ShareItem('GIF', Icons.gif_box_outlined),
    ];
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 16.h,
        crossAxisSpacing: 12.w,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (context, i) {
        final it = items[i];
        return Column(
          children: [
            InkWell(
              onTap: () async {
                if (i == 2 && (videoUrl != null && videoUrl!.isNotEmpty)) {
                  // Copy link as simple "save" placeholder
                  await Clipboard.setData(ClipboardData(text: videoUrl!));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Video link copied')),
                    );
                  }
                } else {
                  Navigator.pop(context);
                }
              },
              customBorder: const CircleBorder(),
              child: CircleAvatar(
                radius: 28.r,
                backgroundColor: const Color(0xFFF2F2F2),
                child: Icon(it.icon, color: Colors.black87),
              ),
            ),
            SizedBox(height: 6.h),
            Text(it.label, style: TextStyle(fontSize: 12.sp)),
          ],
        );
      },
    );
  }
}

class _ShareItem {
  _ShareItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _BoomerangMedia extends StatefulWidget {
  const _BoomerangMedia({required this.videoUrl, required this.posterUrl});
  final String? videoUrl;
  final String? posterUrl;

  @override
  State<_BoomerangMedia> createState() => _BoomerangMediaState();
}

class _BoomerangMediaState extends State<_BoomerangMedia> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    // Performance: avoid initializing inline video players in the scrolling feed.
    // Videos play in the full-screen pager/viewer instead. This dramatically
    // reduces jank and memory pressure while scrolling the feed.
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show poster only in the feed; tap opens full-screen viewer/pager.
    if (widget.posterUrl != null && widget.posterUrl!.isNotEmpty) {
      final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
      final targetWidth = (MediaQuery.of(context).size.width - 32.w);
      final cacheW = (targetWidth * devicePixelRatio).round();
      return Image(
        image: ResizeImage.resizeIfNeeded(
          cacheW,
          null,
          NetworkImage(widget.posterUrl!),
        ),
        fit: BoxFit.cover,
      );
    }
    // Lightweight non-black placeholder with play hint to avoid jarring black screens.
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
}
