import 'package:boomerang/core/widgets/instagram_shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Full-screen reel skeleton — IG dark shimmer per control cluster.
class BoomerangPagerShimmer extends StatelessWidget {
  const BoomerangPagerShimmer({super.key, this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.viewPaddingOf(context).top;
    return ColoredBox(
      // Keep fullscreen loading neutral gray (not pure black) for softer UX.
      color: const Color(0xFF2A2A2A),
      child: ShimmerScope(
        brightness: Brightness.dark,
        duration: const Duration(milliseconds: 1700),
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
              left: 0,
              right: 0,
              top: top + 8.h,
              child: Row(
                children: [
                  SizedBox(
                    width: 48.w,
                    height: 48.w,
                    child:
                        onBack != null
                            ? IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(
                                Icons.arrow_back,
                                color: Colors.white,
                              ),
                              onPressed: onBack,
                            )
                            : const SizedBox.shrink(),
                  ),
                  const Spacer(),
                  ShimmerBone(
                    width: 72.w,
                    height: 22.h,
                    borderRadius: BorderRadius.circular(8.r),
                    phaseShift: 0.05,
                  ),
                  Spacer(),
                  SizedBox(width: 48.w),
                ],
              ),
            ),
            Positioned(
              right: 12.w,
              bottom: 100.h,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShimmerCircle(size: 62.r, phaseShift: 0.07),
                  SizedBox(height: 8.h),
                  ShimmerBone(
                    width: 28.w,
                    height: 14.h,
                    borderRadius: BorderRadius.circular(6.r),
                    phaseShift: 0.09,
                  ),
                  SizedBox(height: 18.h),
                  ShimmerCircle(size: 62.r, phaseShift: 0.11),
                  SizedBox(height: 8.h),
                  ShimmerBone(
                    width: 28.w,
                    height: 14.h,
                    borderRadius: BorderRadius.circular(6.r),
                    phaseShift: 0.13,
                  ),
                  SizedBox(height: 18.h),
                  ShimmerCircle(size: 62.r, phaseShift: 0.15),
                  SizedBox(height: 18.h),
                  ShimmerCircle(size: 62.r, phaseShift: 0.17),
                ],
              ),
            ),
            Positioned(
              left: 12.w,
              bottom: 24.h,
              right: 88.w,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      ShimmerCircle(size: 52.r, phaseShift: 0.02),
                      SizedBox(width: 10.w),
                      ShimmerBone(
                        width: 140.w,
                        height: 20.h,
                        borderRadius: BorderRadius.circular(8.r),
                        phaseShift: 0.04,
                      ),
                    ],
                  ),
                  SizedBox(height: 10.h),
                  ShimmerBone(
                    width: double.infinity,
                    height: 15.h,
                    borderRadius: BorderRadius.circular(8.r),
                    phaseShift: 0.06,
                  ),
                  SizedBox(height: 8.h),
                  ShimmerBone(
                    width: 220.w,
                    height: 15.h,
                    borderRadius: BorderRadius.circular(8.r),
                    phaseShift: 0.08,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
