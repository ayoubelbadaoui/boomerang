import 'package:boomerang/core/widgets/live_avatar.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/feed/presentation/sheets/profile_preview_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

enum FollowMode { following, followers }

class FollowListSheet extends ConsumerWidget {
  const FollowListSheet({super.key, required this.mode, required this.userId});
  final FollowMode mode;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = userId;
    final stream =
        mode == FollowMode.following
            ? ref.watch(followRepoProvider).watchFollowing(uid)
            : ref.watch(followRepoProvider).watchFollowers(uid);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
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
              mode == FollowMode.following ? 'Following' : 'Followers',
              style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 12.h),
            const Divider(),
            SizedBox(height: 12.h),
            Expanded(
              child: StreamBuilder(
                stream: stream,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        mode == FollowMode.following
                            ? 'No following yet'
                            : 'No followers yet',
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: 14.sp,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => SizedBox(height: 8.h),
                    itemBuilder: (context, i) {
                      final d = docs[i].data();
                      final name = (d['userName'] ?? 'User') as String;
                      final avatarFallback = d['userAvatar'] as String?;
                      final handle =
                          '@${name.replaceAll(' ', '_').toLowerCase()}';
                      final userId = (d['userId'] ?? '') as String;
                      return _FollowListTile(
                        name: name,
                        handle: handle,
                        avatarFallback: avatarFallback,
                        userId: userId,
                        showFollowBack: mode == FollowMode.followers,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FollowListTile extends ConsumerStatefulWidget {
  const _FollowListTile({
    required this.name,
    required this.handle,
    required this.avatarFallback,
    required this.userId,
    required this.showFollowBack,
  });

  final String name;
  final String handle;
  final String? avatarFallback;
  final String userId;
  final bool showFollowBack;

  @override
  ConsumerState<_FollowListTile> createState() => _FollowListTileState();
}

class _FollowListTileState extends ConsumerState<_FollowListTile> {
  bool _loading = false;

  Future<void> _followBack() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await ref.read(followRepoProvider).followOrRequest(widget.userId);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final iFollow = widget.userId.isNotEmpty
        ? (ref.watch(isFollowingStreamProvider(widget.userId)).value ?? false)
        : false;
    final canFollowBack = widget.showFollowBack && !iFollow;

    return ListTile(
      onTap: () => _showProfilePreview(
        context,
        widget.handle,
        widget.userId,
      ),
      leading: SizedBox(
        width: 44.r,
        height: 44.r,
        child: LiveAvatar(userId: widget.userId, fallbackUrl: widget.avatarFallback, size: 44.r),
      ),
      title: Text(
        widget.name,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        widget.handle,
        style: const TextStyle(color: Colors.black54),
      ),
      trailing: canFollowBack
          ? SizedBox(
              height: 30.h,
              child: ElevatedButton(
                onPressed: _loading ? null : _followBack,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 14.w),
                  shape: const StadiumBorder(),
                  textStyle: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: _loading
                    ? SizedBox(
                        width: 14.w,
                        height: 14.w,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Follow back'),
              ),
            )
          : const Icon(Icons.chevron_right),
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
    builder:
        (_) => ProfilePreviewSheet(
          userId: userId,
          handle: handle,
        ),
  );
}
