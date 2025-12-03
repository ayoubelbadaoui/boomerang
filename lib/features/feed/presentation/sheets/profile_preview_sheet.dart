import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/profile/presentation/sheets/follow_list_sheet.dart';
import 'package:boomerang/features/profile/presentation/other_user_profile_page.dart';

class ProfilePreviewSheet extends ConsumerStatefulWidget {
  const ProfilePreviewSheet({
    super.key,
    required this.userId,
    required this.handle,
    required this.avatarUrl,
    this.subtitle,
  });
  final String userId;
  final String handle;
  final String? avatarUrl;
  final String? subtitle;

  @override
  ConsumerState<ProfilePreviewSheet> createState() =>
      _ProfilePreviewSheetState();
}

class _ProfilePreviewSheetState extends ConsumerState<ProfilePreviewSheet> {
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
    final me = ref.watch(currentUserProfileProvider).value;
    final isSelf = me?.uid == widget.userId;
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
                    builder: (_) =>
                        OtherUserProfilePage(userId: widget.userId),
                  ),
                );
              },
              customBorder: const CircleBorder(),
              child: CircleAvatar(
                radius: 44.r,
                backgroundImage:
                    widget.avatarUrl != null
                        ? ResizeImage.resizeIfNeeded(
                          (88.r * MediaQuery.of(context).devicePixelRatio)
                              .round(),
                          (88.r * MediaQuery.of(context).devicePixelRatio)
                              .round(),
                          NetworkImage(widget.avatarUrl!),
                        )
                        : null,
                backgroundColor: const Color(0xFFF2F2F2),
              ),
            ),
            SizedBox(height: 12.h),
            InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        OtherUserProfilePage(userId: widget.userId),
                  ),
                );
              },
              child: Text(
                widget.handle,
                style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w800),
              ),
            ),
            if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
              SizedBox(height: 6.h),
              Text(
                widget.subtitle!,
                style: TextStyle(color: Colors.black54, fontSize: 14.sp),
              ),
            ],
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
                          (_isFollowing == null || _loading)
                              ? null
                              : _toggleFollow,
                      icon: Icon(
                        _isFollowing == true
                            ? Icons.check
                            : Icons.person_add_alt_1,
                      ),
                      label: Text(
                        _isFollowing == true ? 'Following' : 'Follow',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isFollowing == true ? Colors.white : Colors.black,
                        foregroundColor:
                            _isFollowing == true ? Colors.black : Colors.white,
                        side:
                            _isFollowing == true
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
                    onPressed: () {},
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
