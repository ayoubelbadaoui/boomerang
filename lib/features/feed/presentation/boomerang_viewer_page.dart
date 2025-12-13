import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:boomerang/features/feed/presentation/sheets/profile_preview_sheet.dart';
import 'package:boomerang/features/feed/presentation/hashtag_feed_page.dart';

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
  late final AnimationController _anim;

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
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _anim.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  Future<void> _like() async {
    final me = ref.read(currentUserProfileProvider).value;
    if (me == null) return;
    await ref
        .read(boomerangRepoProvider)
        .toggleLike(boomerangId: widget.id, userId: me.uid);
  }

  void _onDoubleTap() async {
    setState(() => _showHeart = true);
    _anim.forward(from: 0);
    await _like();
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() => _showHeart = false);
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

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final handle =
        '@${(data['userName'] ?? 'user').toString().replaceAll(' ', '_').toLowerCase()}';
    final avatar = data['userAvatar'] as String?;
    final image = data['imageUrl'] as String?;
    final video = data['videoUrl'] as String?;
    final likes = (data['likes'] ?? 0) as int;
    final userId = (data['userId'] ?? '') as String;
    final double topInset = MediaQuery.of(context).viewPadding.top;
    final tags =
        ((data['hashtags'] as List?)?.cast<String>() ?? const <String>[]);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onDoubleTap: _onDoubleTap,
              behavior: HitTestBehavior.opaque,
              child:
                  _controller != null && _controller!.value.isInitialized
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
          if (_showHeart)
            Center(
              child: ScaleTransition(
                scale: Tween(begin: 0.6, end: 1.2).animate(
                  CurvedAnimation(parent: _anim, curve: Curves.easeOutBack),
                ),
                child: Icon(
                  Icons.favorite,
                  color: Colors.white.withOpacity(0.9),
                  size: 100.r,
                ),
              ),
            ),
          // Top bar
          Positioned(
            left: 8.w,
            top: topInset + 8.h,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            ),
          ),
          // Bottom info row
          Positioned(
            left: 12.w,
            bottom: 20.h,
            right: 88.w,
            child: Row(
              children: [
                InkWell(
                  onTap:
                      () =>
                          _showProfilePreview(context, handle, avatar, userId),
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
                    onBackgroundImageError: avatar != null ? (_, __) {} : null,
                  ),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: InkWell(
                    onTap:
                        () => _showProfilePreview(
                          context,
                          handle,
                          avatar,
                          userId,
                        ),
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
          if (tags.isNotEmpty)
            Positioned(
              left: 12.w,
              bottom: 58.h,
              right: 88.w,
              child: Wrap(
                spacing: 8.w,
                runSpacing: 6.h,
                children: tags.take(4).map((t) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => HashtagFeedPage(tag: t),
                        ),
                      );
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Text(
                        '#$t',
                        style: TextStyle(color: Colors.white, fontSize: 12.sp),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          // Right side actions
          Positioned(
            right: 12.w,
            bottom: 20.h,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ViewerLikeButton(postId: widget.id, data: data),
                SizedBox(height: 12.h),
                _ActionCircle(
                  icon: Icons.chat_bubble_rounded,
                  onTap: () => _showCommentsSheet(context, widget.id),
                ),
                SizedBox(height: 12.h),
                _ActionCircle(
                  icon: Icons.reply_outlined,
                  onTap: () => _showShareSheet(context, video, handle),
                ),
                SizedBox(height: 4.h),
                Text(
                  '$likes',
                  style: TextStyle(color: Colors.white, fontSize: 12.sp),
                ),
              ],
            ),
          ),
        ],
      ),
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

class _ViewerLikeButton extends ConsumerWidget {
  const _ViewerLikeButton({required this.postId, required this.data});
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
        child: Icon(
          isLiked ? Icons.favorite : Icons.favorite_border,
          color: isLiked ? Colors.red : Colors.white,
          size: 30.r,
        ),
      ),
    );
  }
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

void _showShareSheet(BuildContext context, String? videoUrl, String handle) {
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _QuickItem(
                    icon: Icons.upload_rounded,
                    label: 'Repost',
                    onTap: () => Share.share(videoUrl ?? handle),
                  ),
                  _QuickItem(
                    avatar: const CircleAvatar(
                      backgroundImage: AssetImage('assets/logo.png'),
                    ),
                    label:
                        handle.length > 10
                            ? '${handle.substring(0, 10)}…'
                            : handle,
                    onTap: () => Share.share(videoUrl ?? handle),
                  ),
                  _QuickItem(
                    icon: Icons.search,
                    label: 'Search',
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
              SizedBox(height: 16.h),
              const Divider(),
            ],
          ),
        ),
      );
    },
  );
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
            decoration: const BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
            ),
            child: Center(child: avatar ?? Icon(icon, color: Colors.white)),
          ),
        ),
        SizedBox(height: 6.h),
        Text(label, style: TextStyle(fontSize: 12.sp, color: Colors.black87)),
      ],
    );
  }
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
                    final likedBy =
                        (c['likedBy'] as List?)?.cast<String>() ??
                        const <String>[];
                    final likes = (c['likes'] ?? 0) as int;
                    return _CommentTile(
                      boomerangId: widget.boomerangId,
                      commentId: commentId,
                      userAvatar: c['userAvatar'] as String?,
                      userName: (c['userName'] ?? 'User') as String,
                      text: (c['text'] ?? '') as String,
                      likes: likes,
                      likedBy: likedBy,
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
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
