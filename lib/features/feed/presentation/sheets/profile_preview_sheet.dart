import 'package:boomerang/core/widgets/live_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/chat/application/chat_providers.dart';
import 'package:boomerang/features/moderation/application/moderation_providers.dart';
import 'package:boomerang/features/moderation/presentation/widgets/block_confirmation_dialog.dart';
import 'package:boomerang/features/moderation/presentation/widgets/report_sheet.dart';
import 'package:boomerang/features/profile/presentation/sheets/follow_list_sheet.dart';
import 'package:boomerang/features/profile/presentation/other_user_profile_page.dart';
import 'package:boomerang/features/profile/infrastructure/follow_repo.dart';

class ProfilePreviewSheet extends ConsumerStatefulWidget {
  const ProfilePreviewSheet({
    super.key,
    required this.userId,
    required this.handle,
    this.avatarUrl,
  });
  final String userId;
  final String handle;
  final String? avatarUrl;

  @override
  ConsumerState<ProfilePreviewSheet> createState() =>
      _ProfilePreviewSheetState();
}

class _ProfilePreviewSheetState extends ConsumerState<ProfilePreviewSheet> {
  bool _loading = false;
  bool _optimisticRequested = false;

  Future<void> _toggleFollow({
    required bool isFollowing,
    required bool requested,
  }) async {
    if (_loading) return;
    setState(() => _loading = true);
    final repo = ref.read(followRepoProvider);
    try {
      if (isFollowing) {
        await repo.unfollow(widget.userId);
        if (mounted) _optimisticRequested = false;
      } else if (requested) {
        await repo.cancelRequest(widget.userId);
        if (mounted) _optimisticRequested = false;
      } else {
        final outcome = await repo.followOrRequest(widget.userId);
        if (mounted) {
          _optimisticRequested = outcome == FollowOutcome.requested;
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentUserProfileProvider).value;
    final isSelf = me?.uid == widget.userId;
    final blockedList = ref.watch(blockedUsersProvider).value ?? const [];
    final isBlocked = blockedList.contains(widget.userId);

    if (isBlocked) {
      return _BlockedPreview(
        userId: widget.userId,
        handle: widget.handle,
        avatarUrl: widget.avatarUrl,
      );
    }

    final isFollowing =
        ref.watch(isFollowingStreamProvider(widget.userId)).value ?? false;
    final outgoing =
        ref.watch(outgoingFollowRequestProvider(widget.userId)).value;
    final requested = _optimisticRequested || (outgoing?.isPending == true);
    final theyFollowMe =
        ref.watch(isFollowedByProvider(widget.userId)).value ?? false;
    final targetProfile =
        ref.watch(userProfileByIdProvider(widget.userId)).value;
    final targetIsPrivate = targetProfile?.isPrivate ?? false;
    final canViewPrivateContent = !targetIsPrivate || isFollowing || isSelf;
    final followLabel =
        isFollowing
            ? 'Following'
            : requested
                ? 'Pending'
                : theyFollowMe
                    ? 'Follow back'
                    : targetIsPrivate
                        ? 'Request'
                        : 'Follow';
    final followIcon =
        isFollowing
            ? Icons.check
            : requested
                ? Icons.schedule
                : Icons.person_add_alt_1;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 5,
              margin: EdgeInsets.only(bottom: 16.h),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            LiveAvatar(
              userId: widget.userId,
              fallbackUrl: widget.avatarUrl,
              size: 88.r,
              enableFullscreen: true,
              heroTag: 'preview_avatar_${widget.userId}',
            ),
            SizedBox(height: 12.h),
            InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OtherUserProfilePage(userId: widget.userId),
                  ),
                );
              },
              child: Text(
                widget.handle,
                style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w800),
              ),
            ),
            Consumer(
              builder: (context, ref, _) {
                final profile = ref.watch(userProfileByIdProvider(widget.userId)).value;
                final bio = profile?.bio ?? '';
                if (bio.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: EdgeInsets.only(top: 6.h),
                  child: Text(
                    bio,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14.sp),
                  ),
                );
              },
            ),
            SizedBox(height: 16.h),
            const Divider(),
            SizedBox(height: 12.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Consumer(
                  builder: (context, ref, _) {
                    final posts = ref.watch(
                      userBoomerangsCountProvider(widget.userId),
                    );
                    final text = posts.maybeWhen(
                      data: (v) => '$v',
                      orElse: () => '0',
                    );
                    return _Stat(value: text, label: 'Bmg.');
                  },
                ),
                Consumer(
                  builder: (context, ref, _) {
                    if (!canViewPrivateContent) {
                      return const _Stat(value: '-', label: 'Followers');
                    }
                    final followers = ref.watch(
                      followersCountProvider(widget.userId),
                    );
                    final text = followers.maybeWhen(
                      data: (v) => '$v',
                      orElse: () => '0',
                    );
                    return _Stat(
                      value: text,
                      label: 'Followers',
                      onTap:
                          () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.white,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(24),
                              ),
                            ),
                            builder:
                                (_) => SizedBox(
                                  height: 500,
                                  child: FollowListSheet(
                                    mode: FollowMode.followers,
                                    userId: widget.userId,
                                  ),
                                ),
                          ),
                    );
                  },
                ),
                Consumer(
                  builder: (context, ref, _) {
                    if (!canViewPrivateContent) {
                      return const _Stat(value: '-', label: 'Following');
                    }
                    final following = ref.watch(
                      followingCountProvider(widget.userId),
                    );
                    final text = following.maybeWhen(
                      data: (v) => '$v',
                      orElse: () => '0',
                    );
                    return _Stat(
                      value: text,
                      label: 'Following',
                      onTap:
                          () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.white,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(24),
                              ),
                            ),
                            builder:
                                (_) => SizedBox(
                                  height: 500,
                                  child: FollowListSheet(
                                    mode: FollowMode.following,
                                    userId: widget.userId,
                                  ),
                                ),
                          ),
                    );
                  },
                ),
                Consumer(
                  builder: (context, ref, _) {
                    final likes = ref.watch(
                      userTotalLikesProvider(widget.userId),
                    );
                    final text = likes.maybeWhen(
                      data: (v) => '$v',
                      orElse: () => '0',
                    );
                    return _Stat(value: text, label: 'Likes');
                  },
                ),
              ],
            ),
            SizedBox(height: 16.h),
            Row(
              children: [
                if (!isSelf)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed:
                          _loading
                              ? null
                              : () => _toggleFollow(
                                    isFollowing: isFollowing,
                                    requested: requested,
                                  ),
                      icon:
                          _loading
                              ? SizedBox(
                                  width: 16.r,
                                  height: 16.r,
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation(Colors.white),
                                  ),
                                )
                              : Icon(followIcon),
                      label: Text(
                        followLabel,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isFollowing ? Colors.white : Colors.black,
                        foregroundColor:
                            isFollowing ? Colors.black : Colors.white,
                        side:
                            isFollowing
                                ? const BorderSide(
                                  color: Colors.black,
                                  width: 1,
                                )
                                : BorderSide.none,
                        shape: const StadiumBorder(),
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                      ),
                    ),
                  ),
                if (!isSelf) SizedBox(width: 12.w),
                if (!isSelf)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final me = ref.read(currentUserProfileProvider).value;
                        if (me == null) return;
                        final modRepo = ref.read(moderationRepoProvider);
                        final iBlocked = await modRepo.isBlocked(
                          checkerUid: me.uid,
                          targetUid: widget.userId,
                        );
                        final theyBlocked = await modRepo.isBlocked(
                          checkerUid: widget.userId,
                          targetUid: me.uid,
                        );
                        if (!context.mounted) return;
                        if (iBlocked || theyBlocked) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Unable to message this user'),
                            ),
                          );
                          return;
                        }
                        if (targetIsPrivate && !isFollowing) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Follow this account to send a message',
                              ),
                            ),
                          );
                          return;
                        }
                        final repo = ref.read(chatRepoProvider);
                        final convId = await repo.getOrCreateConversation(
                          [me.uid, widget.userId],
                        );
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        context.push('/chat/$convId');
                      },
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Message'),
                      style: OutlinedButton.styleFrom(
                        shape: const StadiumBorder(),
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                      ),
                    ),
                  ),
              ],
            ),
            if (!isSelf) ...[
              SizedBox(height: 8.h),
              Consumer(
                builder: (context, ref, _) {
                  final blockedList =
                      ref.watch(blockedUsersProvider).value ?? const [];
                  final isBlocked = blockedList.contains(widget.userId);
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          showReportSheet(
                            context,
                            reportedUid: widget.userId,
                          );
                        },
                        icon: Icon(Icons.flag_outlined,
                            size: 18.r, color: Colors.redAccent),
                        label: Text(
                          'Report',
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                      SizedBox(width: 16.w),
                      TextButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          if (isBlocked) {
                            await showUnblockDialog(
                              context,
                              ref: ref,
                              blockedUid: widget.userId,
                              handle: widget.handle,
                            );
                          } else {
                            await showBlockDialog(
                              context,
                              ref: ref,
                              blockedUid: widget.userId,
                              handle: widget.handle,
                            );
                          }
                        },
                        icon: Icon(
                          isBlocked
                              ? Icons.lock_open_rounded
                              : Icons.block_rounded,
                          size: 18.r,
                          color: isBlocked
                              ? Colors.blueAccent
                              : Colors.redAccent,
                        ),
                        label: Text(
                          isBlocked ? 'Unblock' : 'Block',
                          style: TextStyle(
                            fontSize: 13.sp,
                            color: isBlocked
                                ? Colors.blueAccent
                                : Colors.redAccent,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BlockedPreview extends ConsumerWidget {
  const _BlockedPreview({
    required this.userId,
    required this.handle,
    required this.avatarUrl,
  });
  final String userId;
  final String handle;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 5,
              margin: EdgeInsets.only(bottom: 16.h),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            LiveAvatar(
              userId: userId,
              fallbackUrl: avatarUrl,
              size: 88.r,
              enableFullscreen: true,
              heroTag: 'preview_blocked_avatar_$userId',
            ),
            SizedBox(height: 12.h),
            Text(
              handle,
              style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 20.h),
            Icon(Icons.block_rounded, size: 32.r, color: Colors.black26),
            SizedBox(height: 8.h),
            Text(
              'You blocked this user',
              style: TextStyle(
                fontSize: 15.sp,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            SizedBox(height: 16.h),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  showUnblockDialog(
                    context,
                    ref: ref,
                    blockedUid: userId,
                    handle: handle,
                  );
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.black, width: 1),
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  'Unblock',
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.onTap});
  final String value;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8.r),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 4.h),
            Text(
              label,
              style: TextStyle(color: Colors.black54, fontSize: 12.sp),
            ),
          ],
        ),
      ),
    );
  }
}
