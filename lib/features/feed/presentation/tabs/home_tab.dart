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
import 'package:boomerang/features/feed/presentation/sheets/qa_sheet.dart';
import 'package:boomerang/features/feed/presentation/sheets/viewers_sheet.dart';
import 'package:boomerang/features/feed/presentation/sheets/ranking_sheet.dart';
// import 'package:boomerang/features/feed/presentation/boomerang_viewer_page.dart';
import 'package:boomerang/features/feed/presentation/boomerang_pager_page.dart';

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
    await _fetchNext();
  }

  @override
  Widget build(BuildContext context) {
    if (_docs.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_docs.isEmpty) {
      return const Center(child: Text('No boomerangs yet'));
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        primary: false,
        controller: _controller,
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 100.h),
        itemCount: _docs.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, __) => SizedBox(height: 16.h),
        itemBuilder: (context, i) {
          if (i >= _docs.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final d = _docs[i];
          final data = d.data();
          return _BoomerangCard(id: d.id, data: data);
        },
      ),
    );
  }
}

class _BoomerangCard extends StatelessWidget {
  const _BoomerangCard({required this.id, required this.data});
  final String id;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final handle =
        '@${(data['userName'] ?? 'user').toString().replaceAll(' ', '_').toLowerCase()}';
    final avatar = data['userAvatar'] as String?;
    final image = data['imageUrl'] as String?; // optional poster
    final video = data['videoUrl'] as String?;
    return ClipRRect(
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
                                (28.r * MediaQuery.of(context).devicePixelRatio)
                                    .round(),
                                (28.r * MediaQuery.of(context).devicePixelRatio)
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
              child: Row(
                children: [
                  InkWell(
                    onTap: () => _showQASheet(context),
                    customBorder: const CircleBorder(),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      padding: EdgeInsets.all(8.r),
                      child: const Icon(
                        Icons.forum_outlined,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  InkWell(
                    onTap: () => _showRankingSheet(context),
                    customBorder: const CircleBorder(),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      padding: EdgeInsets.all(8.r),
                      child: const Icon(Icons.leaderboard, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 12.w,
              bottom: 12.h,
              child: Row(
                children: [
                  _CircleBtn(
                    icon: Icons.chat_bubble_rounded,
                    onTap: () => _showCommentsSheet(context, id, data),
                  ),
                  SizedBox(width: 8.w),
                  _CircleBtn(
                    icon: Icons.reply_outlined,
                    onTap: () => _showShareSheet(context, data),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 20.w,
              bottom: 22.h,
              child: _LikeButton(postId: id, data: data),
            ),
            Positioned(
              left: 12.w,
              bottom: 52.h,
              child: Row(
                children: [
                  Text(
                    handle,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.sp,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    'Description',
                    style: TextStyle(color: Colors.white70, fontSize: 14.sp),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({required this.icon, this.onTap});
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
        padding: EdgeInsets.all(8.r),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _LikeButton extends ConsumerWidget {
  const _LikeButton({required this.postId, required this.data});
  final String postId;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProfileProvider).value;
    final likedBy =
        (data['likedBy'] as List?)?.cast<String>() ?? const <String>[];
    final isLiked = me != null && likedBy.contains(me.uid);
    return InkWell(
      onTap:
          me == null
              ? null
              : () => ref
                  .read(boomerangRepoProvider)
                  .toggleLike(
                    boomerangId: postId,
                    userId: me.uid,
                    actorName:
                        me.nickname.isNotEmpty ? me.nickname : me.fullName,
                    actorAvatar: me.avatarUrl,
                  ),
      customBorder: const CircleBorder(),
      child: AnimatedScale(
        scale: isLiked ? 1.1 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: SvgPicture.asset(
          'assets/heart.svg',
          width: 30.r,
          height: 30.r,
          colorFilter: ColorFilter.mode(
            isLiked ? Colors.red : Colors.white,
            BlendMode.srcIn,
          ),
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
  });
  final String postId;
  final Map<String, dynamic> data;
  final Widget child;
  @override
  ConsumerState<_DoubleTapLikeArea> createState() => _DoubleTapLikeAreaState();
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
    await ref
        .read(boomerangRepoProvider)
        .toggleLike(
          boomerangId: widget.postId,
          userId: me.uid,
          actorName: me.nickname.isNotEmpty ? me.nickname : me.fullName,
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

void _showQASheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const QASheet(),
  );
}

void _showRankingSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const RankingSheet(),
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
            (context, controller) => _CommentsSheet(
              boomerangId: boomerangId,
              scrollController: controller,
            ),
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
                    final commentId = docs[i].id;
                    return _CommentTile(
                      boomerangId: widget.boomerangId,
                      commentId: commentId,
                      userAvatar: c['userAvatar'] as String?,
                      userName: (c['userName'] ?? 'User') as String,
                      text: (c['text'] ?? '') as String,
                      likes: (c['likes'] ?? 0) as int,
                      likedBy:
                          (c['likedBy'] as List?)?.cast<String>() ??
                          const <String>[],
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
                    final profileAsync = ref.read(currentUserProfileProvider);
                    final user = profileAsync.value;
                    // Clear input immediately and dismiss keyboard for snappy UX
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

class _CommentTile extends ConsumerWidget {
  const _CommentTile({
    required this.boomerangId,
    required this.commentId,
    required this.userAvatar,
    required this.userName,
    required this.text,
    required this.likes,
    required this.likedBy,
  });
  final String boomerangId;
  final String commentId;
  final String? userAvatar;
  final String userName;
  final String text;
  final int likes;
  final List<String> likedBy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProfileProvider).value;
    final isLiked = me != null && likedBy.contains(me.uid);

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22.r,
                backgroundImage:
                    userAvatar != null
                        ? ResizeImage.resizeIfNeeded(
                          (44.r * MediaQuery.of(context).devicePixelRatio)
                              .round(),
                          (44.r * MediaQuery.of(context).devicePixelRatio)
                              .round(),
                          NetworkImage(userAvatar!),
                        )
                        : null,
                onBackgroundImageError: userAvatar != null ? (_, __) {} : null,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            userName,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16.sp,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.more_horiz),
                        ),
                      ],
                    ),
                    Text(text, style: TextStyle(fontSize: 14.sp, height: 1.4)),
                    SizedBox(height: 8.h),
                    Row(
                      children: [
                        InkWell(
                          onTap:
                              me == null
                                  ? null
                                  : () => ref
                                      .read(commentsRepoProvider)
                                      .toggleLike(
                                        boomerangId: boomerangId,
                                        commentId: commentId,
                                        userId: me.uid,
                                      ),
                          customBorder: const CircleBorder(),
                          child: Row(
                            children: [
                              Icon(
                                isLiked
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                size: 20,
                                color: Colors.black87,
                              ),
                              SizedBox(width: 6.w),
                              Text('$likes', style: TextStyle(fontSize: 13.sp)),
                            ],
                          ),
                        ),
                        SizedBox(width: 16.w),
                        InkWell(
                          onTap: () => _openReply(context, ref),
                          child: Text(
                            'Reply',
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          _RepliesList(boomerangId: boomerangId, commentId: commentId),
        ],
      ),
    );
  }

  void _openReply(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Add reply...',
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
                    final me = ref.read(currentUserProfileProvider).value;
                    final text = controller.text.trim();
                    if (me == null || text.isEmpty) return;
                    controller.clear();
                    FocusScope.of(context).unfocus();
                    await ref
                        .read(commentsRepoProvider)
                        .addReply(
                          boomerangId: boomerangId,
                          parentCommentId: commentId,
                          userId: me.uid,
                          userName:
                              me.nickname.isNotEmpty
                                  ? me.nickname
                                  : me.fullName,
                          userAvatar: me.avatarUrl,
                          text: text,
                        );
                    if (context.mounted) Navigator.pop(context);
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
        );
      },
    );
  }
}

class _RepliesList extends ConsumerWidget {
  const _RepliesList({required this.boomerangId, required this.commentId});
  final String boomerangId;
  final String commentId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream =
        FirebaseFirestore.instance
            .collection('boomerangs')
            .doc(boomerangId)
            .collection('comments')
            .doc(commentId)
            .collection('replies')
            .orderBy('createdAt', descending: true)
            .snapshots();
    return StreamBuilder(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(left: 56.w, top: 8.h),
          child: Column(
            children:
                docs.map((d) {
                  final r = d.data();
                  return Padding(
                    padding: EdgeInsets.only(bottom: 10.h),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 16.r,
                          backgroundImage:
                              (r['userAvatar'] as String?) != null
                                  ? ResizeImage.resizeIfNeeded(
                                    (32.r *
                                            MediaQuery.of(
                                              context,
                                            ).devicePixelRatio)
                                        .round(),
                                    (32.r *
                                            MediaQuery.of(
                                              context,
                                            ).devicePixelRatio)
                                        .round(),
                                    NetworkImage(r['userAvatar']),
                                  )
                                  : null,
                          onBackgroundImageError:
                              (r['userAvatar'] as String?) != null
                                  ? (_, __) {}
                                  : null,
                        ),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r['userName'] ?? 'User',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14.sp,
                                ),
                              ),
                              Text(
                                r['text'] ?? '',
                                style: TextStyle(fontSize: 13.sp),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
          ),
        );
      },
    );
  }
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
