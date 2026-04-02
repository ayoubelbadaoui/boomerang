import 'package:boomerang/features/moderation/application/moderation_providers.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Shows a confirmation dialog to block a user. Returns `true` if the user was
/// successfully blocked, `false` otherwise.
Future<bool> showBlockDialog(
  BuildContext context, {
  required WidgetRef ref,
  required String blockedUid,
  required String handle,
  String? blockedName,
  String? blockedAvatar,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Block $handle?',
        style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700),
      ),
      content: Text(
        'They won\'t be able to find your profile, message you, '
        'or see your content. They won\'t be notified.',
        style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade700),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            'Cancel',
            style: TextStyle(fontSize: 15.sp, color: Colors.grey.shade600),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'Block',
            style: TextStyle(
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
              color: Colors.redAccent,
            ),
          ),
        ),
      ],
    ),
  );

  if (confirmed != true) return false;

  final me = ref.read(currentUserProfileProvider).value;
  if (me == null) return false;

  try {
    await ref.read(moderationRepoProvider).blockUser(
          blockerUid: me.uid,
          blockedUid: blockedUid,
          blockedName: blockedName,
          blockedAvatar: blockedAvatar,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$handle has been blocked')),
      );
    }
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to block user')),
      );
    }
    return false;
  }
}

/// Shows a confirmation dialog to unblock a user. Returns `true` if the user
/// was successfully unblocked, `false` otherwise.
Future<bool> showUnblockDialog(
  BuildContext context, {
  required WidgetRef ref,
  required String blockedUid,
  required String handle,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Unblock $handle?',
        style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700),
      ),
      content: Text(
        'They will be able to find your profile, message you, '
        'and see your content again.',
        style: TextStyle(fontSize: 14.sp, color: Colors.grey.shade700),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            'Cancel',
            style: TextStyle(fontSize: 15.sp, color: Colors.grey.shade600),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'Unblock',
            style: TextStyle(
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
              color: Colors.blueAccent,
            ),
          ),
        ),
      ],
    ),
  );

  if (confirmed != true) return false;

  final me = ref.read(currentUserProfileProvider).value;
  if (me == null) return false;

  try {
    await ref.read(moderationRepoProvider).unblockUser(
          blockerUid: me.uid,
          blockedUid: blockedUid,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$handle has been unblocked')),
      );
    }
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to unblock user')),
      );
    }
    return false;
  }
}
