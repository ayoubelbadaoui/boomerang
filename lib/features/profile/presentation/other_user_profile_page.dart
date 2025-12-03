import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/profile/presentation/widgets/user_boomerangs_grid_for_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
                    child: _FollowButton(userId: userId),
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
  const _FollowButton({required this.userId});
  final String userId;
  @override
  ConsumerState<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<_FollowButton> {
  bool _loading = false;
  bool? _isFollowing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final repo = ref.read(followRepoProvider);
      final v = await repo.isFollowing(widget.userId);
      if (mounted) setState(() => _isFollowing = v);
    });
  }

  Future<void> _toggleFollow() async {
    if (_loading || _isFollowing == null) return;
    setState(() => _loading = true);
    final repo = ref.read(followRepoProvider);
    try {
      if (_isFollowing == true) {
        await repo.unfollow(widget.userId);
        if (mounted) setState(() => _isFollowing = false);
      } else {
        await repo.follow(widget.userId);
        if (mounted) setState(() => _isFollowing = true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: (_isFollowing == null || _loading) ? null : _toggleFollow,
      icon: Icon(_isFollowing == true ? Icons.check : Icons.person_add_alt_1),
      label: Text(_isFollowing == true ? 'Following' : 'Follow'),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.black, width: 1),
        padding: EdgeInsets.symmetric(vertical: 14.h),
        shape: StadiumBorder(
          side: BorderSide(color: Colors.black, width: 1.w),
        ),
        backgroundColor: _isFollowing == true ? Colors.white : Colors.black,
        foregroundColor: _isFollowing == true ? Colors.black : Colors.white,
      ),
    );
  }
}


