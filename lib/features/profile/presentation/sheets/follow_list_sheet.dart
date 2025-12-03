import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/feed/presentation/sheets/profile_preview_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

enum FollowMode { following, followers }

class FollowListSheet extends ConsumerWidget {
  const FollowListSheet({super.key, required this.mode});
  final FollowMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProfileProvider).value;
    final uid = me?.uid;
    if (uid == null) {
      return const SizedBox.shrink();
    }
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
                      final avatar = d['userAvatar'] as String?;
                      final handle =
                          '@${name.replaceAll(' ', '_').toLowerCase()}';
                      final userId = (d['userId'] ?? '') as String;
                      return ListTile(
                        onTap:
                            () => _showProfilePreview(context, handle, avatar, userId),
                        leading: CircleAvatar(
                          radius: 22.r,
                          backgroundImage:
                              avatar != null
                                  ? ResizeImage.resizeIfNeeded(
                                    (44.r *
                                            MediaQuery.of(
                                              context,
                                            ).devicePixelRatio)
                                        .round(),
                                    (44.r *
                                            MediaQuery.of(
                                              context,
                                            ).devicePixelRatio)
                                        .round(),
                                    NetworkImage(avatar),
                                  )
                                  : null,
                          onBackgroundImageError:
                              avatar != null ? (_, __) {} : null,
                        ),
                        title: Text(
                          name,
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          handle,
                          style: const TextStyle(color: Colors.black54),
                        ),
                        trailing: const Icon(Icons.chevron_right),
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
          subtitle: '',
        ),
  );
}
