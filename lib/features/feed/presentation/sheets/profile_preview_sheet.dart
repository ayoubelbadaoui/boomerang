import 'package:boomerang/core/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/chat/application/chat_providers.dart';
import 'package:boomerang/features/profile/presentation/sheets/follow_list_sheet.dart';
import 'package:boomerang/features/profile/presentation/other_user_profile_page.dart';
import 'package:boomerang/features/profile/infrastructure/follow_repo.dart';

class ProfilePreviewSheet extends ConsumerStatefulWidget {
  const ProfilePreviewSheet({
    super.key,
    required this.userId,
    required this.handle,
    required this.avatarUrl,
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

  Future<void> _toggleFollow({required bool isFollowing}) async {
    if (_loading) return;
    setState(() => _loading = true);
    final repo = ref.read(followRepoProvider);
    try {
      if (isFollowing) {
        await repo.unfollow(widget.userId);
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
    final isFollowing =
        ref.watch(isFollowingStreamProvider(widget.userId)).value ?? false;
    final outgoing =
        ref.watch(outgoingFollowRequestProvider(widget.userId)).value;
    final requested = _optimisticRequested || (outgoing?.isPending == true);
    final theyFollowMe =
        ref.watch(isFollowedByProvider(widget.userId)).value ?? false;
    final followLabel =
        isFollowing
            ? 'Following'
            : requested
                ? 'Pending'
                : theyFollowMe
                    ? 'Follow back'
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
            InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OtherUserProfilePage(userId: widget.userId),
                  ),
                );
              },
              customBorder: const CircleBorder(),
              child: AppAvatar(url: widget.avatarUrl, size: 88.r),
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
                    style: TextStyle(color: Colors.black54, fontSize: 14.sp),
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
                          (requested || _loading)
                              ? null
                              : () => _toggleFollow(isFollowing: isFollowing),
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
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final me = ref.read(currentUserProfileProvider).value;
                      if (me == null) return;
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
