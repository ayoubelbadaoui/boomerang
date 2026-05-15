import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/chat/application/chat_providers.dart';
import 'package:boomerang/features/moderation/application/moderation_providers.dart';
import 'package:boomerang/features/moderation/presentation/widgets/block_confirmation_dialog.dart';
import 'package:boomerang/features/moderation/presentation/widgets/report_sheet.dart';
import 'package:boomerang/features/profile/domain/user_profile.dart';
import 'package:boomerang/features/profile/application/follow_controller.dart';
import 'package:boomerang/features/profile/application/profile_refresh_controller.dart';
import 'package:boomerang/features/profile/application/user_boomerangs_by_user_controller.dart';
import 'package:boomerang/features/profile/presentation/sheets/follow_list_sheet.dart';
import 'package:boomerang/features/profile/presentation/widgets/user_boomerangs_grid_for_user.dart';
import 'package:boomerang/core/widgets/profile_loading_skeleton.dart';
import 'package:boomerang/core/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

class OtherUserProfilePage extends ConsumerStatefulWidget {
  const OtherUserProfilePage({super.key, required this.userId});
  final String userId;

  @override
  ConsumerState<OtherUserProfilePage> createState() =>
      _OtherUserProfilePageState();
}

class _OtherUserProfilePageState extends ConsumerState<OtherUserProfilePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(profileRefreshControllerProvider.notifier)
          .onProfileOpened(widget.userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final userId = widget.userId;
    final asyncProfile = ref.watch(userProfileByIdProvider(userId));
    final me = ref.watch(currentUserProfileProvider).value;
    final isSelf = me?.uid == userId;
    final blockedList = ref.watch(blockedUsersProvider).value ?? const [];
    final isBlocked = blockedList.contains(userId);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
        ),
        centerTitle: true,
        title: asyncProfile.maybeWhen(
          data:
              (p) => Text(
                (p?.nickname.isNotEmpty == true
                    ? p!.nickname
                    : p?.fullName ?? ''),
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
          orElse: () => const Text('Profile'),
        ),
        actions:
            isSelf
                ? null
                : [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.black),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onSelected: (value) {
                      final profile = asyncProfile.value;
                      final handle =
                          profile != null && profile.nickname.isNotEmpty
                              ? profile.handle
                              : '@user';
                      if (value == 'report') {
                        showReportSheet(context, reportedUid: userId);
                      } else if (value == 'block') {
                        showBlockDialog(
                          context,
                          ref: ref,
                          blockedUid: userId,
                          handle: handle,
                          blockedName: profile?.nickname,
                          blockedAvatar: profile?.avatarUrl,
                        );
                      } else if (value == 'unblock') {
                        showUnblockDialog(
                          context,
                          ref: ref,
                          blockedUid: userId,
                          handle: handle,
                        );
                      }
                    },
                    itemBuilder:
                        (_) => [
                          const PopupMenuItem(
                            value: 'report',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.flag_outlined,
                                  color: Colors.redAccent,
                                ),
                                SizedBox(width: 8),
                                Text('Report'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: isBlocked ? 'unblock' : 'block',
                            child: Row(
                              children: [
                                Icon(
                                  isBlocked
                                      ? Icons.lock_open_rounded
                                      : Icons.block_rounded,
                                  color:
                                      isBlocked
                                          ? Colors.blueAccent
                                          : Colors.redAccent,
                                ),
                                const SizedBox(width: 8),
                                Text(isBlocked ? 'Unblock' : 'Block'),
                              ],
                            ),
                          ),
                        ],
                  ),
                ],
      ),
      body: asyncProfile.when(
        loading:
            () => const ProfileLoadingSkeleton(
              variant: ProfileLoadingVariant.otherProfile,
            ),
        error: (e, _) => Center(child: Text('Failed to load profile: $e')),
        data: (p) {
          if (isBlocked) {
            return _BlockedProfileBody(userId: userId, profile: p);
          }
          final isPrivate = p?.isPrivate ?? false;
          return _ProfileBody(
            userId: userId,
            profile: p,
            isSelf: isSelf,
            isPrivate: isPrivate,
          );
        },
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({
    required this.userId,
    required this.profile,
    required this.isSelf,
    required this.isPrivate,
  });

  final String userId;
  final UserProfile? profile;
  final bool isSelf;
  final bool isPrivate;

  void _openFollowList(BuildContext context, FollowMode mode, bool canView) {
    if (!canView) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (_) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            minChildSize: 0.3,
            builder:
                (_, controller) => FollowListSheet(mode: mode, userId: userId),
          ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = profile;
    final social = ref.watch(profileSocialStateProvider(userId));
    final isFollowing = social.followRelationshipStatus == FollowState.approved;
    final canViewContent = !isPrivate || isFollowing || isSelf;

    return RefreshIndicator(
      color: Colors.black,
      onRefresh: () async {
        await ref
            .read(profileRefreshControllerProvider.notifier)
            .refreshProfile(userId, forceRefresh: true);
        await ref
            .read(userBoomerangsByUserControllerProvider(userId).notifier)
            .refresh();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: 20.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: 8.h),
            AppAvatar(
              url: p?.avatarUrl,
              size: 96.r,
              enableFullscreen: true,
              heroTag: 'other_profile_avatar_$userId',
            ),
            SizedBox(height: 12.h),
            if (p != null && p.nickname.isNotEmpty)
              Text(
                '@${p.nickname.replaceAll(' ', '_').toLowerCase()}',
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700),
              ),
            SizedBox(height: 6.h),
            if (p != null && p.bio.isNotEmpty)
              Text(
                p.bio,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14.sp),
                textAlign: TextAlign.center,
              ),
            SizedBox(height: 20.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Consumer(
                  builder: (context, ref, _) {
                    final posts = ref.watch(
                      userBoomerangsCountProvider(userId),
                    );
                    final value = posts.maybeWhen(
                      data: (v) => '$v',
                      orElse: () => '0',
                    );
                    return _Stat(value: value, label: 'Bmg.');
                  },
                ),
                GestureDetector(
                  onTap:
                      () => _openFollowList(
                        context,
                        FollowMode.followers,
                        canViewContent,
                      ),
                  child: _Stat(
                    value: '${social.followerCount}',
                    label: 'Followers',
                  ),
                ),
                GestureDetector(
                  onTap:
                      () => _openFollowList(
                        context,
                        FollowMode.following,
                        canViewContent,
                      ),
                  child: _Stat(
                    value: '${social.followingCount}',
                    label: 'Following',
                  ),
                ),
                Consumer(
                  builder: (context, ref, _) {
                    final likes = ref.watch(userTotalLikesProvider(userId));
                    final value = likes.maybeWhen(
                      data: (v) => '$v',
                      orElse: () => '0',
                    );
                    return _Stat(value: value, label: 'Likes');
                  },
                ),
              ],
            ),
            SizedBox(height: 16.h),
            if (!isSelf)
              Row(
                children: [
                  Expanded(
                    child: _FollowButton(userId: userId, isPrivate: isPrivate),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(child: _MessageButton(userId: userId)),
                ],
              ),
            if (!isSelf)
              Consumer(
                builder: (context, ref, _) {
                  final pending = ref.watch(
                    incomingRequestPendingProvider(userId),
                  );
                  if (!pending) return const SizedBox.shrink();
                  return _IncomingRequestBanner(userId: userId);
                },
              ),
            SizedBox(height: 16.h),
            Divider(height: 1.h, color: Colors.black12),
            SizedBox(height: 12.h),
            if (canViewContent)
              UserBoomerangsGridForUser(userId: userId)
            else
              _PrivateAccountNotice(),
            SizedBox(height: 80.h),
          ],
        ),
      ),
    );
  }
}

class _PrivateAccountNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 40.h),
      child: Column(
        children: [
          Container(
            width: 72.r,
            height: 72.r,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black, width: 2),
            ),
            child: Icon(Icons.lock_outline, size: 32.r, color: Colors.black),
          ),
          SizedBox(height: 16.h),
          Text(
            'This Account is Private',
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6.h),
          Text(
            'Follow this account to see their boomerangs.',
            style: TextStyle(fontSize: 14.sp, color: Colors.black54),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _BlockedProfileBody extends ConsumerWidget {
  const _BlockedProfileBody({required this.userId, required this.profile});

  final String userId;
  final UserProfile? profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = profile;
    final handle = p != null && p.nickname.isNotEmpty ? p.handle : '@user';
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 32.h),
            AppAvatar(
              url: p?.avatarUrl,
              size: 96.r,
              enableFullscreen: true,
              heroTag: 'other_profile_private_avatar_$userId',
            ),
            SizedBox(height: 12.h),
            if (p != null && p.nickname.isNotEmpty)
              Text(
                handle,
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700),
              ),
            SizedBox(height: 40.h),
            Container(
              width: 72.r,
              height: 72.r,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black26, width: 2),
              ),
              child: Icon(
                Icons.block_rounded,
                size: 32.r,
                color: Colors.black26,
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'You blocked $handle',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'They can\'t see your profile or content, '
              'message you, or follow you.',
              style: TextStyle(fontSize: 14.sp, color: Colors.black45),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24.h),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed:
                    () => showUnblockDialog(
                      context,
                      ref: ref,
                      blockedUid: userId,
                      handle: handle,
                    ),
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
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 4.h),
        Text(label, style: TextStyle(fontSize: 12.sp, color: Colors.black54)),
      ],
    );
  }
}

class _FollowButton extends ConsumerStatefulWidget {
  const _FollowButton({required this.userId, required this.isPrivate});
  final String userId;
  final bool isPrivate;
  @override
  ConsumerState<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<_FollowButton> {
  Future<void> _toggle(FollowState state) async {
    try {
      await ref
          .read(followFlowControllerProvider.notifier)
          .toggleRelationship(
            targetUserId: widget.userId,
            targetIsPrivate: widget.isPrivate,
            currentState: state,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update follow status: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final blockedSet =
        ref.watch(blockedUsersProvider).value?.toSet() ?? const <String>{};
    final iBlockedThem = blockedSet.contains(widget.userId);
    if (iBlockedThem) return const SizedBox.shrink();

    final state = ref.watch(followStateProvider(widget.userId));
    final loading = ref.watch(isFollowActionInFlightProvider(widget.userId));
    final onPressed = loading ? null : () => _toggle(state);

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon:
          loading
              ? SizedBox(
                width: 16.r,
                height: 16.r,
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
              : Icon(
                state == FollowState.approved
                    ? Icons.check
                    : Icons.person_add_alt_1,
              ),
      label: Text(followButtonLabelForState(state)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.black, width: 1),
        padding: EdgeInsets.symmetric(vertical: 14.h),
        shape: StadiumBorder(side: BorderSide(color: Colors.black, width: 1.w)),
        backgroundColor:
            state == FollowState.approved ? Colors.white : Colors.black,
        foregroundColor:
            state == FollowState.approved ? Colors.black : Colors.white,
        disabledForegroundColor: Colors.black45,
        disabledBackgroundColor: Colors.grey.shade200,
      ),
    );
  }
}

class _MessageButton extends ConsumerStatefulWidget {
  const _MessageButton({required this.userId});
  final String userId;

  @override
  ConsumerState<_MessageButton> createState() => _MessageButtonState();
}

class _MessageButtonState extends ConsumerState<_MessageButton> {
  bool _loading = false;

  Future<void> _openChat() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
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
      if (iBlocked || theyBlocked) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to message this user')),
          );
        }
        return;
      }
      final targetProfile =
          ref.read(userProfileByIdProvider(widget.userId)).value;
      final isFollowing =
          ref.read(isFollowingStreamProvider(widget.userId)).value ?? false;
      if ((targetProfile?.isPrivate ?? false) && !isFollowing) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Follow this account to send a message'),
            ),
          );
        }
        return;
      }
      final repo = ref.read(chatRepoProvider);
      final convId = await repo.getOrCreateConversation([
        me.uid,
        widget.userId,
      ]);
      if (!mounted) return;
      context.push('/chat/$convId');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _loading ? null : _openChat,
      icon:
          _loading
              ? SizedBox(
                width: 16.r,
                height: 16.r,
                child: const CircularProgressIndicator(strokeWidth: 2),
              )
              : const Icon(Icons.chat_bubble_outline),
      label: const Text('Message'),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.black, width: 1),
        padding: EdgeInsets.symmetric(vertical: 14.h),
        shape: const StadiumBorder(),
      ),
    );
  }
}

class _IncomingRequestBanner extends ConsumerStatefulWidget {
  const _IncomingRequestBanner({required this.userId});
  final String userId;

  @override
  ConsumerState<_IncomingRequestBanner> createState() =>
      _IncomingRequestBannerState();
}

class _IncomingRequestBannerState
    extends ConsumerState<_IncomingRequestBanner> {
  Future<void> _accept() async {
    try {
      await ref
          .read(followFlowControllerProvider.notifier)
          .approveIncomingRequest(senderId: widget.userId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not accept follow request: $e')),
      );
    }
  }

  Future<void> _reject() async {
    try {
      await ref
          .read(followFlowControllerProvider.notifier)
          .rejectIncomingRequest(senderId: widget.userId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reject follow request: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(isFollowActionInFlightProvider(widget.userId));
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F6),
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Follow request pending',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp),
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : _reject,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24.r),
                    ),
                    side: const BorderSide(color: Colors.black54),
                  ),
                  child: const Text('Reject'),
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: ElevatedButton(
                  onPressed: busy ? null : _accept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24.r),
                    ),
                  ),
                  child:
                      busy
                          ? SizedBox(
                            width: 16.r,
                            height: 16.r,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                          : const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
