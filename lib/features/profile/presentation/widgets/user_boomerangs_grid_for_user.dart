import 'package:boomerang/core/utils/color_opacity.dart';
import 'package:boomerang/features/profile/application/user_boomerangs_by_user_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:boomerang/features/profile/presentation/profile_reels_page.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:boomerang/core/widgets/boomerang_grid_shimmers.dart';
import 'package:boomerang/core/widgets/boomerang_grid_thumbnail.dart';
import 'package:boomerang/core/widgets/instagram_shimmer.dart';

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
      loading: () => const ProfilePostsMasonryShimmer(),
      error: (e, _) => Center(child: Text('Failed to load posts: $e')),
      data: (s) {
        if (s.docs.isEmpty && s.isLoading) {
          return const ProfilePostsMasonryShimmer();
        }
        if (s.docs.isEmpty) {
          return const Center(child: Text('No posts yet'));
        }
        return Column(
          children: [
            ShimmerScope(
              child: MasonryGridView.count(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: s.docs.length,
                crossAxisCount: 2,
                mainAxisSpacing: 12.h,
                crossAxisSpacing: 12.w,
                itemBuilder: (context, index) {
                  final doc = s.docs[index];
                  final data = doc.data();
                  final imageUrl = data['imageUrl'] as String?;
                  final videoUrl = data['videoUrl'] as String?;
                  final aspectRatio = index.isEven ? 9 / 14 : 9 / 11;
                  return InkWell(
                    onTap: () {
                      final items =
                          s.docs
                              .map((d) => (id: d.id, data: d.data()))
                              .toList();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder:
                              (_) => ProfileReelsPage(
                                initialItems: items,
                                initialIndex: index,
                                hasMore: s.hasMore,
                                onLoadMore:
                                    () =>
                                        ref
                                            .read(
                                              userBoomerangsByUserControllerProvider(
                                                widget.userId,
                                              ).notifier,
                                            )
                                            .fetchNext(),
                              ),
                        ),
                      );
                    },
                    child: AspectRatio(
                      aspectRatio: aspectRatio,
                      child: _GridTile(
                        imageUrl: imageUrl,
                        videoUrl: videoUrl,
                        phaseShift: index * 0.02,
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: 8.h),
            if (s.isLoading)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 12.h),
                child: const ProfilePostsMasonryShimmer(itemCount: 2),
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
  const _GridTile({
    required this.imageUrl,
    required this.videoUrl,
    required this.phaseShift,
  });
  final String? imageUrl;
  final String? videoUrl;
  final double phaseShift;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cacheWidth = computeCacheWidthForLogicalWidth(
          constraints.maxWidth,
          MediaQuery.devicePixelRatioOf(context),
          maxPx: 1200,
        );
        return BoomerangGridThumbnail(
          imageUrl: imageUrl,
          borderRadius: BorderRadius.circular(12.r),
          cacheWidth: cacheWidth,
          phaseShift: phaseShift,
          overlays: [
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
        );
      },
    );
  }
}
