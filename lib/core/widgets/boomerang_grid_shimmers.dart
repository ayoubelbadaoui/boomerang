import 'package:boomerang/core/widgets/instagram_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

/// Masonry placeholder for profile “posts” grids (matches `UserBoomerangsGrid`).
class ProfilePostsMasonryShimmer extends StatelessWidget {
  const ProfilePostsMasonryShimmer({
    super.key,
    this.itemCount = 6,
    this.crossAxisCount = 2,
    this.mainAxisSpacing,
    this.crossAxisSpacing,
    this.padding,
    this.wrapWithScope = true,
  });

  final int itemCount;
  final int crossAxisCount;
  final double? mainAxisSpacing;
  final double? crossAxisSpacing;
  final EdgeInsetsGeometry? padding;
  /// Set false when already under [ShimmerScope] (e.g. [ProfileLoadingSkeleton]).
  final bool wrapWithScope;

  @override
  Widget build(BuildContext context) {
    final mainGap = mainAxisSpacing ?? 12.h;
    final crossGap = crossAxisSpacing ?? 12.w;
    final grid = MasonryGridView.count(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: padding ?? EdgeInsets.zero,
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: mainGap,
      crossAxisSpacing: crossGap,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        final aspectRatio = index.isEven ? 9 / 14 : 9 / 11;
        final shift = index * 0.03;
        return AspectRatio(
          aspectRatio: aspectRatio,
          child: ShimmerBone(
            width: double.infinity,
            height: double.infinity,
            borderRadius: BorderRadius.circular(12.r),
            phaseShift: shift % 1.0,
          ),
        );
      },
    );
    if (!wrapWithScope) return grid;
    return ShimmerScope(child: grid);
  }
}

/// 3-column saved grid (matches `SavedBoomerangsGrid`).
class SavedPostsGridShimmer extends StatelessWidget {
  const SavedPostsGridShimmer({
    super.key,
    this.itemCount = 9,
    this.crossAxisCount = 3,
    this.childAspectRatio = 3 / 4,
    this.wrapWithScope = true,
  });

  final int itemCount;
  final int crossAxisCount;
  final double childAspectRatio;
  final bool wrapWithScope;

  @override
  Widget build(BuildContext context) {
    final grid = GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: itemCount,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 16.h,
        crossAxisSpacing: 16.w,
        childAspectRatio: childAspectRatio,
      ),
      itemBuilder: (context, i) {
        return ShimmerBone(
          width: double.infinity,
          height: double.infinity,
          borderRadius: BorderRadius.circular(12.r),
          phaseShift: (i * 0.04) % 1.0,
        );
      },
    );
    if (!wrapWithScope) return grid;
    return ShimmerScope(child: grid);
  }
}

/// Explore “Bmg.” masonry tile + caption row (matches `DiscoverTab` `_BmgGridContent`).
class DiscoverExploreGridShimmer extends StatelessWidget {
  const DiscoverExploreGridShimmer({
    super.key,
    this.itemCount = 6,
    this.padding,
    this.wrapWithScope = true,
  });

  final int itemCount;
  final EdgeInsetsGeometry? padding;
  final bool wrapWithScope;

  @override
  Widget build(BuildContext context) {
    final grid = MasonryGridView.count(
      padding:
          padding ??
          EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      crossAxisCount: 2,
      mainAxisSpacing: 16.h,
      crossAxisSpacing: 16.w,
      itemCount: itemCount,
      itemBuilder: (context, i) {
        final aspectRatio = i.isEven ? 9 / 14 : 9 / 11;
        final shift = i * 0.035;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: aspectRatio,
              child: ShimmerBone(
                width: double.infinity,
                height: double.infinity,
                borderRadius: BorderRadius.circular(18.r),
                phaseShift: shift % 1.0,
              ),
            ),
            SizedBox(height: 8.h),
            Row(
              children: [
                ShimmerCircle(size: 24.r, phaseShift: (shift + 0.02) % 1.0),
                SizedBox(width: 8.w),
                Expanded(
                  child: ShimmerBone(
                    height: 14.h,
                    borderRadius: BorderRadius.circular(8.r),
                    phaseShift: (shift + 0.04) % 1.0,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (!wrapWithScope) return grid;
    return ShimmerScope(child: grid);
  }
}

/// Hashtag masonry without caption row (matches `HashtagFeedPage` ratios).
class HashtagMasonryShimmer extends StatelessWidget {
  const HashtagMasonryShimmer({
    super.key,
    this.itemCount = 6,
    this.padding,
    this.wrapWithScope = true,
  });

  final int itemCount;
  final EdgeInsetsGeometry? padding;
  final bool wrapWithScope;

  @override
  Widget build(BuildContext context) {
    final grid = MasonryGridView.count(
      padding:
          padding ??
          EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      crossAxisCount: 2,
      mainAxisSpacing: 16.h,
      crossAxisSpacing: 16.w,
      itemCount: itemCount,
      itemBuilder: (context, i) {
        final aspectRatio = i.isEven ? 9 / 13 : 9 / 10;
        final shift = i * 0.035;
        return AspectRatio(
          aspectRatio: aspectRatio,
          child: ShimmerBone(
            width: double.infinity,
            height: double.infinity,
            borderRadius: BorderRadius.circular(18.r),
            phaseShift: shift % 1.0,
          ),
        );
      },
    );
    if (!wrapWithScope) return grid;
    return ShimmerScope(child: grid);
  }
}

/// Discover tab — user search results list.
class DiscoverUsersListShimmer extends StatelessWidget {
  const DiscoverUsersListShimmer({
    super.key,
    this.rowCount = 10,
    this.wrapWithScope = true,
  });

  final int rowCount;
  final bool wrapWithScope;

  @override
  Widget build(BuildContext context) {
    final list = ListView.separated(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      itemCount: rowCount,
      separatorBuilder: (_, __) => SizedBox(height: 8.h),
      itemBuilder: (context, i) {
        final shift = i * 0.04;
        return Row(
          children: [
            ShimmerCircle(size: 48.r, phaseShift: shift % 1.0),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerBone(
                    width: 160.w,
                    height: 16.h,
                    borderRadius: BorderRadius.circular(8.r),
                    phaseShift: (shift + 0.02) % 1.0,
                  ),
                  SizedBox(height: 8.h),
                  ShimmerBone(
                    width: 120.w,
                    height: 13.h,
                    borderRadius: BorderRadius.circular(8.r),
                    phaseShift: (shift + 0.04) % 1.0,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
    if (!wrapWithScope) return list;
    return ShimmerScope(child: list);
  }
}

/// Discover tab — hashtag search list.
class DiscoverHashtagListShimmer extends StatelessWidget {
  const DiscoverHashtagListShimmer({
    super.key,
    this.rowCount = 12,
    this.wrapWithScope = true,
  });

  final int rowCount;
  final bool wrapWithScope;

  @override
  Widget build(BuildContext context) {
    final list = ListView.separated(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      itemCount: rowCount,
      separatorBuilder: (_, __) => SizedBox(height: 8.h),
      itemBuilder: (context, i) {
        final shift = i * 0.035;
        return Row(
          children: [
            ShimmerBone(
              width: 40.r,
              height: 40.r,
              borderRadius: BorderRadius.circular(10.r),
              phaseShift: shift % 1.0,
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: ShimmerBone(
                height: 18.h,
                borderRadius: BorderRadius.circular(8.r),
                phaseShift: (shift + 0.03) % 1.0,
              ),
            ),
            ShimmerBone(
              width: 24.r,
              height: 24.r,
              borderRadius: BorderRadius.circular(6.r),
              phaseShift: (shift + 0.05) % 1.0,
            ),
          ],
        );
      },
    );
    if (!wrapWithScope) return list;
    return ShimmerScope(child: list);
  }
}
