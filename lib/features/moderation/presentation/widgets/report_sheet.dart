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
    this.commentId,
    this.showBlockOption = false,
    this.reportedName,
    this.reportedAvatar,
    this.reportedHandle,
  });

  final String reportedUid;
  final String? boomerangId;
  final String? commentId;

  /// When true, shows an "Also block this account" toggle. The reporter then
  /// blocks [reportedUid] as part of submitting the report.
  final bool showBlockOption;
  final String? reportedName;
  final String? reportedAvatar;
  final String? reportedHandle;

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  ReportReason? _selectedReason;
  final _detailsController = TextEditingController();
  bool _submitting = false;
  bool _alsoBlock = false;

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
        commentId: widget.commentId,
        type: widget.commentId != null
            ? ReportType.comment
            : widget.boomerangId != null
                ? ReportType.boomerang
                : ReportType.user,
        reason: _selectedReason!,
        details: _detailsController.text.trim().isEmpty
            ? null
            : _detailsController.text.trim(),
        createdAt: DateTime.now(),
      );
      await ref.read(moderationRepoProvider).submitReport(report);

      final shouldBlock = widget.showBlockOption && _alsoBlock;
      if (shouldBlock) {
        await ref.read(moderationRepoProvider).blockUser(
              blockerUid: me.uid,
              blockedUid: widget.reportedUid,
              blockedName: widget.reportedName,
              blockedAvatar: widget.reportedAvatar,
            );
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shouldBlock
                ? 'Report submitted and account blocked.'
                : 'Report submitted. We\'ll review it shortly.',
          ),
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
    final String title;
    if (widget.commentId != null) {
      title = 'Report this comment';
    } else if (widget.boomerangId != null) {
      title = 'Report this boomerang';
    } else {
      title = 'Report this user';
    }

    final media = MediaQuery.of(context);
    // Reserve space for the pinned submit button so it never clips off-screen
    // on short devices, large text scale, or when the keyboard is open.
    final scrollMaxHeight = (media.size.height -
            media.viewInsets.bottom -
            media.padding.vertical -
            180.h)
        .clamp(160.0, media.size.height * 0.55);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16.w,
          8.h,
          16.w,
          media.viewInsets.bottom + 16.h,
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
              title,
              style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 4.h),
            Text(
              'Why are you reporting?',
              style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade600),
            ),
            SizedBox(height: 12.h),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: scrollMaxHeight),
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RadioGroup<ReportReason>(
                      groupValue: _selectedReason,
                      onChanged: (v) => setState(() => _selectedReason = v),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final reason in ReportReason.values)
                            RadioListTile<ReportReason>(
                              title: Text(
                                ReportEntity.reasonLabel(reason),
                                style: TextStyle(fontSize: 15.sp),
                              ),
                              value: reason,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              activeColor: Colors.redAccent,
                            ),
                        ],
                      ),
                    ),
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
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12.w,
                          vertical: 10.h,
                        ),
                      ),
                    ),
                    if (widget.showBlockOption) ...[
                      SizedBox(height: 4.h),
                      CheckboxListTile(
                        value: _alsoBlock,
                        onChanged: (v) =>
                            setState(() => _alsoBlock = v ?? false),
                        activeColor: Colors.redAccent,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        title: Text(
                          widget.reportedHandle?.isNotEmpty == true
                              ? 'Also block ${widget.reportedHandle}'
                              : 'Also block this account',
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          'They won\'t be able to find your profile, '
                          'message you, or see your content.',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SizedBox(height: 12.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    _selectedReason != null && !_submitting ? _submit : null,
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
  String? commentId,
  bool showBlockOption = false,
  String? reportedName,
  String? reportedAvatar,
  String? reportedHandle,
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
      commentId: commentId,
      showBlockOption: showBlockOption,
      reportedName: reportedName,
      reportedAvatar: reportedAvatar,
      reportedHandle: reportedHandle,
    ),
  );
}
