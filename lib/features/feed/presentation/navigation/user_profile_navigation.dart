import 'package:boomerang/core/navigation/own_profile_navigation.dart';
import 'package:boomerang/features/feed/presentation/sheets/profile_preview_sheet.dart';
import 'package:boomerang/features/profile/presentation/other_user_profile_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:boomerang/core/navigation/own_profile_navigation.dart'
    show isCurrentUserId, navigateToOwnProfile;

void openUserProfilePreview(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String handle,
  String? avatarUrl,
}) {
  if (isCurrentUserId(ref, userId)) {
    navigateToOwnProfile(context, ref);
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder:
        (_) => ProfilePreviewSheet(
          userId: userId,
          handle: handle,
          avatarUrl: avatarUrl,
        ),
  );
}

void openUserProfilePage(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
}) {
  if (isCurrentUserId(ref, userId)) {
    navigateToOwnProfile(context, ref);
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => OtherUserProfilePage(userId: userId),
    ),
  );
}
