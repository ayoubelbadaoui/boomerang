import 'package:boomerang/features/feed/presentation/sheets/profile_preview_sheet.dart';
import 'package:boomerang/features/feed/presentation/widgets/comments_sheet.dart';
import 'package:boomerang/features/moderation/presentation/widgets/report_sheet.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:share_plus/share_plus.dart';

class BoomerangOverlay extends ConsumerWidget {
  const BoomerangOverlay({
    super.key,
    required this.boomerangId,
    required this.data,
    this.showTopBar = true,
  });

  final String boomerangId;
  final Map<String, dynamic> data;
  final bool showTopBar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userName = (data['userName'] ?? 'user').toString();
    final handle =
        '@${userName.replaceAll(' ', '_').toLowerCase()}';
    final avatar = data['userAvatar'] as String?;
    final video = data['videoUrl'] as String?;
    final likes = (data['likes'] ?? 0) as int;
    final userId = (data['userId'] ?? '') as String;
    final caption = (data['caption'] ?? '') as String;
    final initialCommentsCount = ((data['commentsCount'] ?? 0) as num).toInt();
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final me = ref.watch(currentUserProfileProvider).value;

    return Stack(
      children: [
        if (showTopBar)
          Positioned(
            left: 0,
            right: 0,
            top: topInset + 8.h,
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                const Spacer(),
                Text(
                  'Reels',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                SizedBox(width: 48.w),
              ],
            ),
          ),
        // Right side actions
        Positioned(
          right: 12.w,
          bottom: 100.h,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ActionBubble(
                child: _LikeIcon(postId: boomerangId, data: data),
              ),
              SizedBox(height: 4.h),
              Text(
                '$likes',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 16.h),
              _ActionBubble(
                onTap: () => _showCommentsSheet(context, boomerangId),
                child: Icon(Icons.chat_bubble_outline_rounded,
                    color: Colors.white, size: 24.r),
              ),
              SizedBox(height: 4.h),
              StreamBuilder(
                stream: ref.watch(commentsRepoProvider).watch(boomerangId),
                builder: (context, snapshot) {
                  final count = snapshot.data?.docs.length ?? initialCommentsCount;
                  return Text(
                    '$count',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
              SizedBox(height: 16.h),
              if (me != null)
                StreamBuilder<bool>(
                  stream: ref
                      .watch(savedRepoProvider)
                      .watchIsSaved(
                          userId: me.uid, boomerangId: boomerangId),
                  initialData: false,
                  builder: (context, snapshot) {
                    final saved = snapshot.data ?? false;
                    return _ActionBubble(
                      onTap: () async {
                        await ref.read(savedRepoProvider).toggleSave(
                              userId: me.uid,
                              boomerangId: boomerangId,
                              boomerangData: data,
                            );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(saved
                                  ? 'Removed from saved'
                                  : 'Saved to your profile'),
                            ),
                          );
                        }
                      },
                      child: Icon(
                        saved
                            ? Icons.bookmark
                            : Icons.bookmark_outline_rounded,
                        color: Colors.white,
                        size: 24.r,
                      ),
                    );
                  },
                ),
              SizedBox(height: 16.h),
              _ActionBubble(
                onTap: () => _showShareSheet(
                  context,
                  video,
                  handle,
                  reportedUid: userId,
                  boomerangId: boomerangId,
                ),
                child: Icon(Icons.send_outlined,
                    color: Colors.white, size: 24.r),
              ),
            ],
          ),
        ),
        // Bottom info: avatar, handle, caption
        Positioned(
          left: 12.w,
          bottom: 24.h,
          right: 60.w,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => _showProfilePreview(
                    context, handle, avatar, userId),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16.r,
                      backgroundImage:
                          avatar != null ? NetworkImage(avatar) : null,
                      onBackgroundImageError:
                          avatar != null ? (_, __) {} : null,
                      backgroundColor: Colors.grey.shade300,
                      child: avatar == null
                          ? Text(
                              userName.isNotEmpty
                                  ? userName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w700,
                                fontSize: 14.sp,
                              ),
                            )
                          : null,
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      handle,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16.sp,
                      ),
                    ),
                  ],
                ),
              ),
              if (caption.isNotEmpty) ...[
                SizedBox(height: 6.h),
                Text(
                  caption,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.sp,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionBubble extends StatelessWidget {
  const _ActionBubble({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(10.r),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
        child: child,
      ),
    );
  }
}

class _LikeIcon extends ConsumerWidget {
  const _LikeIcon({required this.postId, required this.data});
  final String postId;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProfileProvider).value;
    final likedBy =
        (data['likedBy'] as List?)?.cast<String>() ?? const <String>[];
    final isLiked = me != null && likedBy.contains(me.uid);
    return GestureDetector(
      onTap: me == null
          ? null
          : () => ref.read(boomerangRepoProvider).toggleLike(
                boomerangId: postId,
                userId: me.uid,
                actorName:
                    me.nickname.isNotEmpty ? me.nickname : me.fullName,
                actorAvatar: me.avatarUrl,
              ),
      child: AnimatedScale(
        scale: isLiked ? 1.1 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Icon(
          isLiked ? Icons.favorite : Icons.favorite_border,
          color: isLiked ? Colors.red : Colors.white,
          size: 24.r,
        ),
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
    builder: (_) => ProfilePreviewSheet(
      userId: userId,
      handle: handle,
      avatarUrl: avatar,
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
        builder: (context, controller) => CommentsSheet(
          boomerangId: boomerangId,
          scrollController: controller,
        ),
      );
    },
  );
}

void _showShareSheet(
  BuildContext context,
  String? videoUrl,
  String handle, {
  required String reportedUid,
  String? boomerangId,
}) {
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
                'Share',
                style:
                    TextStyle(fontSize: 24.sp, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 16.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ShareOption(
                    icon: Icons.copy,
                    label: 'Copy link',
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied')),
                      );
                    },
                  ),
                  _ShareOption(
                    icon: Icons.share_outlined,
                    label: 'Share',
                    // ignore: deprecated_member_use
                    onTap: () => Share.share(videoUrl ?? handle),
                  ),
                  _ShareOption(
                    icon: Icons.flag_outlined,
                    label: 'Report',
                    onTap: () {
                      Navigator.pop(context);
                      showReportSheet(
                        context,
                        reportedUid: reportedUid,
                        boomerangId: boomerangId,
                      );
                    },
                  ),
                ],
              ),
              SizedBox(height: 16.h),
            ],
          ),
        ),
      );
    },
  );
}

class _ShareOption extends StatelessWidget {
  const _ShareOption(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 28.r,
            backgroundColor: const Color(0xFFF2F2F2),
            child: Icon(icon, color: Colors.black87),
          ),
          SizedBox(height: 6.h),
          Text(label, style: TextStyle(fontSize: 12.sp)),
        ],
      ),
    );
  }
}
