import 'package:boomerang/features/moderation/application/moderation_providers.dart';
import 'package:boomerang/features/moderation/domain/report_entity.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ReportSheet extends ConsumerStatefulWidget {
  const ReportSheet({
    super.key,
    required this.reportedUid,
    this.boomerangId,
  });

  final String reportedUid;
  final String? boomerangId;

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  ReportReason? _selectedReason;
  final _detailsController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedReason == null) return;
    final me = ref.read(currentUserProfileProvider).value;
    if (me == null) return;

    setState(() => _submitting = true);
    try {
      final report = ReportEntity(
        reporterUid: me.uid,
        reportedUid: widget.reportedUid,
        boomerangId: widget.boomerangId,
        type: widget.boomerangId != null
            ? ReportType.boomerang
            : ReportType.user,
        reason: _selectedReason!,
        details: _detailsController.text.trim().isEmpty
            ? null
            : _detailsController.text.trim(),
        createdAt: DateTime.now(),
      );
      await ref.read(moderationRepoProvider).submitReport(report);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report submitted. We\'ll review it shortly.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to submit report')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBoomerang = widget.boomerangId != null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16.w,
          8.h,
          16.w,
          MediaQuery.viewInsetsOf(context).bottom + 16.h,
        ),
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
              isBoomerang ? 'Report this boomerang' : 'Report this user',
              style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 4.h),
            Text(
              'Why are you reporting?',
              style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade600),
            ),
            SizedBox(height: 12.h),
            ...ReportReason.values.map((reason) {
              return RadioListTile<ReportReason>(
                title: Text(
                  ReportEntity.reasonLabel(reason),
                  style: TextStyle(fontSize: 15.sp),
                ),
                value: reason,
                groupValue: _selectedReason,
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: Colors.redAccent,
                onChanged: (v) => setState(() => _selectedReason = v),
              );
            }),
            SizedBox(height: 8.h),
            TextField(
              controller: _detailsController,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'Additional details (optional)',
                hintStyle: TextStyle(fontSize: 14.sp),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              ),
            ),
            SizedBox(height: 12.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedReason != null && !_submitting
                    ? _submit
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _submitting
                    ? SizedBox(
                        height: 20.r,
                        width: 20.r,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Submit Report',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper to show the report sheet from anywhere.
void showReportSheet(
  BuildContext context, {
  required String reportedUid,
  String? boomerangId,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => ReportSheet(
      reportedUid: reportedUid,
      boomerangId: boomerangId,
    ),
  );
}
