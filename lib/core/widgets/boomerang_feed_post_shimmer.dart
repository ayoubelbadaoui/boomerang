import 'package:boomerang/core/widgets/instagram_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Skeleton matching [home_tab] feed card — each block runs its own IG-style shimmer.
class BoomerangFeedPostShimmer extends StatelessWidget {
  const BoomerangFeedPostShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24.r),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: ShimmerBone(
                      width: double.infinity,
                      height: double.infinity,
                      borderRadius: BorderRadius.zero,
                      phaseShift: 0,
                    ),
                  ),
                  Positioned(
                    left: 18.w,
                    top: 16.h,
                    child: Row(
                      children: [
                        ShimmerCircle(size: 36.r, phaseShift: 0.02),
                        SizedBox(width: 10.w),
                        ShimmerBone(
                          width: 120.w,
                          height: 16.h,
                          borderRadius: BorderRadius.circular(8.r),
                          phaseShift: 0.04,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 20.w,
                    top: 18.h,
                    child: ShimmerCircle(size: 48.r, phaseShift: 0.06),
                  ),
                  Positioned(
                    left: 12.w,
                    bottom: 20.h,
                    child: Row(
                      children: [
                        ShimmerCircle(size: 48.r, phaseShift: 0.08),
                        SizedBox(width: 8.w),
                        ShimmerCircle(size: 48.r, phaseShift: 0.1),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 18.w,
                    bottom: 24.h,
                    child: ShimmerCircle(size: 36.r, phaseShift: 0.12),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBone(
                  width: 140.w,
                  height: 16.h,
                  borderRadius: BorderRadius.circular(8.r),
                  phaseShift: 0.14,
                ),
                SizedBox(height: 8.h),
                ShimmerBone(
                  width: double.infinity,
                  height: 14.h,
                  borderRadius: BorderRadius.circular(8.r),
                  phaseShift: 0.16,
                ),
                SizedBox(height: 6.h),
                ShimmerBone(
                  width: 200.w,
                  height: 14.h,
                  borderRadius: BorderRadius.circular(8.r),
                  phaseShift: 0.18,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
