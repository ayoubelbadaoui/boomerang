import 'package:boomerang/core/utils/color_opacity.dart';
import 'package:boomerang/features/profile/application/user_boomerangs_by_user_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:boomerang/features/feed/presentation/boomerang_viewer_page.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

class UserBoomerangsGridForUser extends ConsumerStatefulWidget {
  const UserBoomerangsGridForUser({super.key, required this.userId});
  final String userId;

  @override
  ConsumerState<UserBoomerangsGridForUser> createState() =>
      _UserBoomerangsGridForUserState();
}

class _UserBoomerangsGridForUserState
    extends ConsumerState<UserBoomerangsGridForUser> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final value =
          ref
              .read(userBoomerangsByUserControllerProvider(widget.userId))
              .valueOrNull;
      if (value == null || value.docs.isEmpty) {
        ref
            .read(
              userBoomerangsByUserControllerProvider(widget.userId).notifier,
            )
            .fetchNext();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(
      userBoomerangsByUserControllerProvider(widget.userId),
    );
    return asyncState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load posts: $e')),
      data: (s) {
        if (s.docs.isEmpty && s.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.docs.isEmpty) {
          return const Center(child: Text('No posts yet'));
        }
        return Column(
          children: [
            MasonryGridView.count(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: s.docs.length,
              crossAxisCount: 2,
              mainAxisSpacing: 12.h,
              crossAxisSpacing: 12.w,
              itemBuilder: (context, index) {
                final doc = s.docs[index];
                final data = doc.data();
                final id = doc.id;
                final imageUrl = data['imageUrl'] as String?;
                final videoUrl = data['videoUrl'] as String?;
                final aspectRatio = index.isEven ? 9 / 14 : 9 / 11;
                return InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BoomerangViewerPage(id: id, data: data),
                      ),
                    );
                  },
                  child: AspectRatio(
                    aspectRatio: aspectRatio,
                    child: _GridTile(imageUrl: imageUrl, videoUrl: videoUrl),
                  ),
                );
              },
            ),
            SizedBox(height: 8.h),
            if (s.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (s.hasMore)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed:
                      () =>
                          ref
                              .read(
                                userBoomerangsByUserControllerProvider(
                                  widget.userId,
                                ).notifier,
                              )
                              .fetchNext(),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.black, width: 1),
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    shape: StadiumBorder(
                      side: BorderSide(color: Colors.black, width: 1.w),
                    ),
                  ),
                  child: Text(
                    'Load more',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({required this.imageUrl, required this.videoUrl});
  final String? imageUrl;
  final String? videoUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12.r),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null && imageUrl!.isNotEmpty)
            Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              cacheWidth: (180 * MediaQuery.devicePixelRatioOf(context)).round(),
              errorBuilder:
                  (_, __, ___) => Container(color: const Color(0xFFF2F2F2)),
            )
          else
            Container(color: const Color(0xFFF2F2F2)),
          if (videoUrl != null && videoUrl!.isNotEmpty)
            Positioned(
              left: 8.w,
              bottom: 8.h,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.fade(0.55),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.play_circle_filled,
                      size: 14,
                      color: Colors.white70,
                    ),
                    SizedBox(width: 4.w),
                    Text(
                      'Preview',
                      style: TextStyle(color: Colors.white, fontSize: 12.sp),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
