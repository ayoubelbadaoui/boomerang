import 'package:boomerang/core/widgets/live_avatar.dart';
import 'package:boomerang/features/feed/presentation/sheets/profile_preview_sheet.dart';
import 'package:boomerang/features/feed/presentation/widgets/comments_sheet.dart';
import 'package:boomerang/features/moderation/presentation/widgets/report_sheet.dart';
import 'package:boomerang/features/profile/application/user_boomerangs_controller.dart';
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
    this.likedOverride,
    this.likesOverride,
    this.onToggleLike,
  });

  final String boomerangId;
  final Map<String, dynamic> data;
  final bool showTopBar;
  final bool? likedOverride;
  final int? likesOverride;
  final void Function(bool liked, int likes)? onToggleLike;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userName = (data['userName'] ?? 'user').toString();
    final handle =
        '@${userName.replaceAll(' ', '_').toLowerCase()}';
    final avatar = data['userAvatar'] as String?;
    final video = data['videoUrl'] as String?;
    final likes = likesOverride ?? (data['likes'] ?? 0) as int;
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
                child: _LikeIcon(
                  postId: boomerangId,
                  data: data,
                  likedOverride: likedOverride,
                  onToggleLike: onToggleLike,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                '$likes',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 18.h),
              _ActionBubble(
                onTap: () => _showCommentsSheet(context, boomerangId, userId),
                child: Icon(Icons.chat_bubble_outline_rounded,
                    color: Colors.white, size: 28.r),
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
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
              SizedBox(height: 18.h),
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
                        size: 28.r,
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
                    color: Colors.white, size: 28.r),
              ),
              if (me != null && me.uid == userId) ...[
                SizedBox(height: 16.h),
                _ActionBubble(
                  onTap: () => _confirmDeleteFromOverlay(
                    context,
                    ref,
                    boomerangId,
                  ),
                  child: Icon(Icons.delete_outline_rounded,
                      color: Colors.white, size: 28.r),
                ),
              ],
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
                    context, handle, userId),
                child: Row(
                  children: [
                    LiveAvatar(
                      userId: userId,
                      fallbackUrl: avatar,
                      size: 44.r,
                    ),
                    SizedBox(width: 10.w),
                    Text(
                      handle,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18.sp,
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
                    fontSize: 14.sp,
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
        padding: EdgeInsets.all(12.r),
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
  const _LikeIcon({
    required this.postId,
    required this.data,
    this.likedOverride,
    this.onToggleLike,
  });
  final String postId;
  final Map<String, dynamic> data;
  final bool? likedOverride;
  final void Function(bool liked, int likes)? onToggleLike;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProfileProvider).value;
    final likedBy =
        (data['likedBy'] as List?)?.cast<String>() ?? const <String>[];
    final isLiked =
        likedOverride ?? (me != null && likedBy.contains(me.uid));
    final currentLikes = (data['likes'] ?? 0) as int;
    return GestureDetector(
      onTap: me == null
          ? null
          : () {
              final nextLiked = !isLiked;
              final nextLikes =
                  currentLikes + (nextLiked ? 1 : -1);
              onToggleLike?.call(nextLiked, nextLikes < 0 ? 0 : nextLikes);
              ref.read(boomerangRepoProvider).toggleLike(
                    boomerangId: postId,
                    userId: me.uid,
                    actorName:
                        me.nickname.isNotEmpty ? me.nickname : me.fullName,
                    actorAvatar: me.avatarUrl,
                  );
            },
      child: AnimatedScale(
        scale: isLiked ? 1.1 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Icon(
          isLiked ? Icons.favorite : Icons.favorite_border,
          color: isLiked ? Colors.red : Colors.white,
          size: 28.r,
        ),
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
    builder: (_) => ProfilePreviewSheet(
      userId: userId,
      handle: handle,
    ),
  );
}

void _showCommentsSheet(
  BuildContext context,
  String boomerangId,
  String postOwnerId,
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
        builder: (context, controller) => CommentsSheet(
          boomerangId: boomerangId,
          scrollController: controller,
          postOwnerId: postOwnerId,
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

void _confirmDeleteFromOverlay(
  BuildContext context,
  WidgetRef ref,
  String boomerangId,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete Boomerang'),
      content: const Text(
        'Are you sure you want to delete this boomerang? This action cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await ref
        .read(userBoomerangsControllerProvider.notifier)
        .deleteBoomerang(boomerangId);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Boomerang deleted')),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to delete: $e')),
    );
  }
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
