import 'dart:async';
import 'dart:io';

import 'package:boomerang/features/feed/application/upload_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class UploadProgressBar extends ConsumerStatefulWidget {
  const UploadProgressBar({super.key});

  @override
  ConsumerState<UploadProgressBar> createState() => _UploadProgressBarState();
}

class _UploadProgressBarState extends ConsumerState<UploadProgressBar> {
  Timer? _autoDismiss;

  @override
  void dispose() {
    _autoDismiss?.cancel();
    super.dispose();
  }

  void _scheduleDismiss() {
    _autoDismiss?.cancel();
    _autoDismiss = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      ref.read(uploadControllerProvider.notifier).dismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final upload = ref.watch(uploadControllerProvider);

    if (upload.phase == UploadPhase.idle) return const SizedBox.shrink();

    if (upload.phase == UploadPhase.done) {
      _scheduleDismiss();
    }

    final (label, color, progressValue) = switch (upload.phase) {
      UploadPhase.processing => ('Processing video...', Colors.black87, null),
      UploadPhase.uploading => (
          'Uploading${upload.progress != null ? ' ${(upload.progress! * 100).toInt()}%' : '...'}',
          Colors.black87,
          upload.progress,
        ),
      UploadPhase.finalizing => ('Finishing up...', Colors.black87, null),
      UploadPhase.done => ('Published!', const Color(0xFF2E7D32), null),
      UploadPhase.failed => (upload.errorMessage ?? 'Upload failed', Colors.red.shade700, null),
      UploadPhase.idle => ('', Colors.black87, null),
    };

    final topInset = MediaQuery.viewPaddingOf(context).top;

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: Container(
        width: double.infinity,
        margin: EdgeInsets.only(
          left: 16.w,
          right: 16.w,
          top: topInset + 6.h,
          bottom: 6.h,
        ),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: upload.phase == UploadPhase.failed
              ? Colors.red.shade50
              : upload.phase == UploadPhase.done
                  ? const Color(0xFFE8F5E9)
                  : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: upload.phase == UploadPhase.failed
                ? Colors.red.shade200
                : upload.phase == UploadPhase.done
                    ? const Color(0xFFA5D6A7)
                    : Colors.grey.shade300,
            width: 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (upload.localPosterPath != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6.r),
                    child: Image.file(
                      File(upload.localPosterPath!),
                      width: 36.w,
                      height: 36.w,
                      fit: BoxFit.cover,
                    ),
                  ),
                  SizedBox(width: 10.w),
                ] else ...[
                  _phaseIcon(upload.phase),
                  SizedBox(width: 10.w),
                ],
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (upload.phase == UploadPhase.failed)
                  GestureDetector(
                    onTap: () =>
                        ref.read(uploadControllerProvider.notifier).retry(),
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700,
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        'Retry',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                if (upload.phase == UploadPhase.done)
                  Icon(Icons.check_circle_rounded,
                      color: const Color(0xFF2E7D32), size: 20.sp),
              ],
            ),
            if (upload.isActive) ...[
              SizedBox(height: 8.h),
              ClipRRect(
                borderRadius: BorderRadius.circular(4.r),
                child: LinearProgressIndicator(
                  value: progressValue,
                  minHeight: 3,
                  backgroundColor: Colors.grey.shade300,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.black87),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _phaseIcon(UploadPhase phase) {
    return switch (phase) {
      UploadPhase.processing =>
        SizedBox(
          width: 18.w,
          height: 18.w,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(Colors.grey.shade600),
          ),
        ),
      UploadPhase.uploading =>
        Icon(Icons.cloud_upload_outlined, size: 20.sp, color: Colors.black54),
      UploadPhase.finalizing =>
        SizedBox(
          width: 18.w,
          height: 18.w,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(Colors.grey.shade600),
          ),
        ),
      UploadPhase.done =>
        Icon(Icons.check_circle_rounded,
            size: 20.sp, color: const Color(0xFF2E7D32)),
      UploadPhase.failed =>
        Icon(Icons.error_outline_rounded, size: 20.sp, color: Colors.red.shade700),
      UploadPhase.idle => const SizedBox.shrink(),
    };
  }
}
