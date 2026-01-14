import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/profile/presentation/widgets/user_boomerangs_grid_for_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:boomerang/features/profile/infrastructure/follow_repo.dart';

class OtherUserProfilePage extends ConsumerWidget {
  const OtherUserProfilePage({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProfile = ref.watch(userProfileByIdProvider(userId));
    final me = ref.watch(currentUserProfileProvider).value;
    final isSelf = me?.uid == userId;
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
          data: (p) => Text(
            (p?.fullName.isNotEmpty == true ? p!.fullName : p?.nickname ?? ''),
            style: TextStyle(
              color: Colors.black,
              fontSize: 18.sp,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          orElse: () => const Text('Profile'),
        ),
      ),
      body: asyncProfile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load profile: $e')),
        data: (p) {
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: 8.h),
                CircleAvatar(
                  radius: 48.r,
                  backgroundImage: p?.avatarUrl != null
                      ? ResizeImage.resizeIfNeeded(
                          (96.r * MediaQuery.of(context).devicePixelRatio)
                              .round(),
                          (96.r * MediaQuery.of(context).devicePixelRatio)
                              .round(),
                          NetworkImage(p!.avatarUrl!),
                        )
                      : null,
                  backgroundColor: const Color(0xFFF2F2F2),
                  child: p?.avatarUrl == null
                      ? const Icon(
                          Icons.person,
                          color: Colors.black26,
                          size: 36,
                        )
                      : null,
                ),
                SizedBox(height: 12.h),
                if (p != null && p.nickname.isNotEmpty)
                  Text(
                    '@${p.nickname.replaceAll(' ', '_').toLowerCase()}',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                SizedBox(height: 6.h),
                if (p != null && p.bio.isNotEmpty)
                  Text(
                    p.bio,
                    style: TextStyle(color: Colors.black54, fontSize: 14.sp),
                    textAlign: TextAlign.center,
                  ),
                SizedBox(height: 20.h),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Consumer(
                      builder: (context, ref, _) {
                        final posts =
                            ref.watch(userBoomerangsCountProvider(userId));
                        final value = posts.maybeWhen(
                          data: (v) => '$v',
                          orElse: () => '0',
                        );
                        return _Stat(value: value, label: 'Bmg.');
                      },
                    ),
                    Consumer(
                      builder: (context, ref, _) {
                        final followers =
                            ref.watch(followersCountProvider(userId));
                        final value = followers.maybeWhen(
                          data: (v) => '$v',
                          orElse: () => '0',
                        );
                        return _Stat(value: value, label: 'Followers');
                      },
                    ),
                    Consumer(
                      builder: (context, ref, _) {
                        final following =
                            ref.watch(followingCountProvider(userId));
                        final value = following.maybeWhen(
                          data: (v) => '$v',
                          orElse: () => '0',
                        );
                        return _Stat(value: value, label: 'Following');
                      },
                    ),
                    Consumer(
                      builder: (context, ref, _) {
                        final likes =
                            ref.watch(userTotalLikesProvider(userId));
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
                  SizedBox(
                    width: double.infinity,
                    child: _FollowButton(
                      userId: userId,
                      isPrivate: p?.isPrivate ?? false,
                    ),
                  ),
                if (!isSelf)
                  Consumer(
                    builder: (context, ref, _) {
                      final incoming =
                          ref.watch(incomingFollowRequestProvider(userId)).value;
                      final pending = incoming?.isPending == true;
                      if (!pending) return const SizedBox.shrink();
                      return _IncomingRequestBanner(userId: userId);
                    },
                  ),
                SizedBox(height: 16.h),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: const [
                    _ModeIcon(icon: Icons.grid_on_rounded, active: true),
                    _ModeIcon(icon: Icons.bookmark_border_rounded),
                    _ModeIcon(icon: Icons.favorite_border_rounded),
                  ],
                ),
                SizedBox(height: 12.h),
                Divider(height: 1.h, color: Colors.black12),
                SizedBox(height: 12.h),
                UserBoomerangsGridForUser(userId: userId),
                SizedBox(height: 80.h),
              ],
            ),
          );
        },
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

class _ModeIcon extends StatelessWidget {
  const _ModeIcon({required this.icon, this.active = false});
  final IconData icon;
  final bool active;
  @override
  Widget build(BuildContext context) {
    return Icon(icon, color: active ? Colors.black : Colors.black38);
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
  bool _loading = false;
  bool _optimisticRequested = false;

  Future<void> _toggleFollow({
    required bool isFollowing,
  }) async {
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
    final isFollowing =
        ref.watch(isFollowingStreamProvider(widget.userId)).value ?? false;
    final outgoing =
        ref.watch(outgoingFollowRequestProvider(widget.userId)).value;
    final requested = _optimisticRequested || (outgoing?.isPending == true);

    final label = isFollowing
        ? 'Following'
        : requested
            ? 'Requested'
            : (widget.isPrivate ? 'Request' : 'Follow');
    final onPressed = (requested || _loading)
        ? null
        : () => _toggleFollow(isFollowing: isFollowing);

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: _loading
          ? SizedBox(
              width: 16.r,
              height: 16.r,
              child: const CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(isFollowing ? Icons.check : Icons.person_add_alt_1),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.black, width: 1),
        padding: EdgeInsets.symmetric(vertical: 14.h),
        shape: StadiumBorder(
          side: BorderSide(color: Colors.black, width: 1.w),
        ),
        backgroundColor: isFollowing ? Colors.white : Colors.black,
        foregroundColor: isFollowing ? Colors.black : Colors.white,
        disabledForegroundColor: Colors.black45,
        disabledBackgroundColor: Colors.grey.shade200,
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
  bool _busy = false;

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(followRepoProvider)
          .acceptRequest(senderId: widget.userId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(followRepoProvider)
          .rejectRequest(senderId: widget.userId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14.sp,
            ),
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _reject,
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
                  onPressed: _busy ? null : _accept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24.r),
                    ),
                  ),
                  child: _busy
                      ? SizedBox(
                          width: 16.r,
                          height: 16.r,
                          child:
                              const CircularProgressIndicator(strokeWidth: 2),
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






