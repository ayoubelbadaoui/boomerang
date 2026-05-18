import 'package:boomerang/core/navigation/home_tab_navigation.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

abstract final class AppRoutes {
  static const home = '/home';
}

/// True when [userId] matches the signed-in Firebase user.
bool isCurrentUserId(WidgetRef ref, String userId) {
  if (userId.isEmpty) return false;
  final authUid = ref.read(firebaseAuthProvider).currentUser?.uid;
  if (authUid != null && authUid == userId) return true;
  final profileUid = ref.read(currentUserProfileProvider).value?.uid;
  return profileUid != null && profileUid == userId;
}

/// Pops the current route (if any), ensures Home is visible, selects Profile tab.
void navigateToOwnProfile(BuildContext context, WidgetRef ref) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) {
    navigator.pop();
  }
  final path = GoRouter.of(context).state.uri.path;
  if (path != AppRoutes.home) {
    context.go(AppRoutes.home);
  }
  ref.read(homeTabIndexProvider.notifier).state = 4;
}
