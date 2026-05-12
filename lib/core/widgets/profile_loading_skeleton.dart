import 'package:boomerang/core/widgets/boomerang_grid_shimmers.dart';
import 'package:boomerang/core/widgets/instagram_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

enum ProfileLoadingVariant { ownProfile, otherProfile }

/// Profile header + posts grid skeleton (IG-style light shimmer).
class ProfileLoadingSkeleton extends StatelessWidget {
  const ProfileLoadingSkeleton({
    super.key,
    required this.variant,
    this.includePostsGrid = true,
  });

  final ProfileLoadingVariant variant;
  final bool includePostsGrid;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: InstagramShimmerColors.lightCanvas,
      child: ShimmerScope(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: 8.h),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ShimmerCircle(size: 96.r, phaseShift: 0),
                  if (variant == ProfileLoadingVariant.ownProfile)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: ShimmerCircle(size: 28.r, phaseShift: 0.03),
                    ),
                ],
              ),
              SizedBox(height: 12.h),
              ShimmerBone(
                width: 160.w,
                height: 18.h,
                borderRadius: BorderRadius.circular(8.r),
                phaseShift: 0.05,
              ),
              SizedBox(height: 8.h),
              ShimmerBone(
                width: double.infinity,
                height: 14.h,
                borderRadius: BorderRadius.circular(8.r),
                phaseShift: 0.07,
              ),
              SizedBox(height: 6.h),
              ShimmerBone(
                width: 220.w,
                height: 14.h,
                borderRadius: BorderRadius.circular(8.r),
                phaseShift: 0.09,
              ),
              SizedBox(height: 20.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _statBone(0.11),
                  _statBone(0.13),
                  _statBone(0.15),
                  _statBone(0.17),
                ],
              ),
              SizedBox(height: 16.h),
              if (variant == ProfileLoadingVariant.ownProfile) ...[
                ShimmerBone(
                  width: double.infinity,
                  height: 48.h,
                  borderRadius: BorderRadius.circular(24.r),
                  phaseShift: 0.19,
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: ShimmerBone(
                        height: 44.h,
                        borderRadius: BorderRadius.circular(22.r),
                        phaseShift: 0.19,
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: ShimmerBone(
                        height: 44.h,
                        borderRadius: BorderRadius.circular(22.r),
                        phaseShift: 0.21,
                      ),
                    ),
                  ],
                ),
              ],
              SizedBox(height: 16.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ShimmerBone(
                    width: 44.r,
                    height: 44.r,
                    borderRadius: BorderRadius.circular(12.r),
                    phaseShift: 0.23,
                  ),
                  ShimmerBone(
                    width: 44.r,
                    height: 44.r,
                    borderRadius: BorderRadius.circular(12.r),
                    phaseShift: 0.25,
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              Divider(height: 1.h, color: Colors.black12),
              SizedBox(height: 12.h),
              if (includePostsGrid)
                const ProfilePostsMasonryShimmer(wrapWithScope: false),
              SizedBox(height: 80.h),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statBone(double shift) {
    return Column(
      children: [
        ShimmerBone(
          width: 36.w,
          height: 18.h,
          borderRadius: BorderRadius.circular(6.r),
          phaseShift: shift % 1.0,
        ),
        SizedBox(height: 6.h),
        ShimmerBone(
          width: 52.w,
          height: 12.h,
          borderRadius: BorderRadius.circular(6.r),
          phaseShift: (shift + 0.02) % 1.0,
        ),
      ],
    );
  }
}
