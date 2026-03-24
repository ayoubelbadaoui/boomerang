import 'dart:developer' as dev;

import 'package:boomerang/core/auth/user_session.dart';
import 'package:boomerang/core/notifications/push_notifications_service.dart';
import 'package:boomerang/core/widgets/avatar.dart';
import 'package:boomerang/features/auth/presentation/login_page.dart';
import 'package:boomerang/features/feed/presentation/home_shell.dart';
import 'package:boomerang/features/profile/application/profile_controller.dart';
import 'package:boomerang/features/profile/application/user_boomerangs_controller.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

/// Instagram-style account switcher presented as a modal bottom sheet.
void showAccountSwitcher(BuildContext context, WidgetRef ref) {
  ref.invalidate(storedAccountsProvider);
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
    ),
    builder: (_) => const _AccountSwitcherBody(),
  );
}

class _AccountSwitcherBody extends ConsumerStatefulWidget {
  const _AccountSwitcherBody();

  @override
  ConsumerState<_AccountSwitcherBody> createState() =>
      _AccountSwitcherBodyState();
}

class _AccountSwitcherBodyState extends ConsumerState<_AccountSwitcherBody> {
  @override
  void initState() {
    super.initState();
    _ensureCurrentAccountStored();
  }

  /// If the active Firebase user is not yet in session storage
  /// (pre-migration case), store them now.
  Future<void> _ensureCurrentAccountStored() async {
    try {
      final auth = ref.read(firebaseAuthProvider);
      final user = auth.currentUser;
      dev.log('[multi-account] switcher._ensure: currentUser=${user?.uid}');
      if (user == null) return;

      final manager = ref.read(multiAccountManagerProvider);
      final accounts = await manager.getAccounts();
      final alreadyStored = accounts.any((a) => a.uid == user.uid);
      dev.log(
        '[multi-account] switcher._ensure: alreadyStored=$alreadyStored '
        'accounts=${accounts.length}',
      );

      if (alreadyStored) {
        // Refresh display name / avatar from live Firestore profile
        final profile = ref.read(currentUserProfileProvider).value;
        if (profile != null) {
          await manager.updateAccountProfile(
            user.uid,
            displayName: profile.fullName.isNotEmpty
                ? profile.fullName
                : profile.nickname,
            photoUrl: profile.avatarUrl,
          );
          if (mounted) ref.invalidate(storedAccountsProvider);
        }
        return;
      }

      final profile = ref.read(currentUserProfileProvider).value;
      dev.log('[multi-account] switcher._ensure: ADDING current user ${user.uid}');
      await manager.addAccount(
        UserSession(
          uid: user.uid,
          email: profile?.email ?? user.email ?? '',
          displayName: profile?.fullName ?? user.displayName ?? '',
          photoUrl: profile?.avatarUrl ?? user.photoURL,
          lastLogin: DateTime.now(),
        ),
      );
      dev.log('[multi-account] switcher._ensure: ADDED, invalidating provider');
      if (mounted) ref.invalidate(storedAccountsProvider);
    } catch (e) {
      dev.log('[multi-account] switcher._ensure FAILED: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final storedAccounts = ref.watch(storedAccountsProvider).valueOrNull ?? [];
    final currentProfile = ref.watch(currentUserProfileProvider).value;
    final currentUid = ref.watch(firebaseAuthProvider).currentUser?.uid;

    final otherAccounts =
        storedAccounts.where((a) => a.uid != currentUid).toList();

    dev.log(
      '[multi-account] switcher.build: currentUid=$currentUid '
      'storedAccounts=${storedAccounts.length} '
      'otherAccounts=${otherAccounts.length} '
      'stored_uids=${storedAccounts.map((a) => "${a.uid.substring(0, 6)}(${a.email})").join(", ")}',
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(0, 8.h, 0, 16.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            SizedBox(height: 16.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Accounts',
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ),
            SizedBox(height: 12.h),

            // Current user — always from live Firestore data
            if (currentUid != null)
              _AccountTile(
                displayName: currentProfile?.fullName.isNotEmpty == true
                    ? currentProfile!.fullName
                    : currentProfile?.nickname ?? '',
                subtitle: currentProfile?.email ?? '',
                photoUrl: currentProfile?.avatarUrl,
                isActive: true,
                onTap: () => Navigator.of(context).pop(),
              ),

            // Other stored accounts
            for (final account in otherAccounts)
              _AccountTile(
                displayName: account.displayName,
                subtitle: account.email,
                photoUrl: account.photoUrl,
                isActive: false,
                onTap: () => _switchTo(context, account),
              ),

            Divider(height: 1.h, indent: 20.w, endIndent: 20.w),

            ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 20.w),
              leading: Container(
                width: 48.r,
                height: 48.r,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.add,
                  color: theme.colorScheme.onSurface,
                  size: 24.r,
                ),
              ),
              title: Text(
                'Add Account',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                context.push(LoginPage.routeName);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _switchTo(BuildContext context, UserSession target) async {
    Navigator.of(context).pop();

    final manager = ref.read(multiAccountManagerProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final goRouter = GoRouter.of(context);

    // Check if we have stored credentials for this account
    final hasCreds =
        await ref.read(sessionStorageProvider).getCredentials(target.uid);

    if (hasCreds == null) {
      if (!context.mounted) return;
      await _showReLoginSheet(context, target);
      return;
    }

    // Snapshot the current account's live profile into storage before
    // switching away, so the switcher shows the correct name/avatar later.
    final currentUid = ref.read(firebaseAuthProvider).currentUser?.uid;
    final currentProfile = ref.read(currentUserProfileProvider).value;
    if (currentUid != null && currentProfile != null) {
      await manager.updateAccountProfile(
        currentUid,
        displayName: currentProfile.fullName.isNotEmpty
            ? currentProfile.fullName
            : currentProfile.nickname,
        photoUrl: currentProfile.avatarUrl,
      );
    }

    // Suppress auth guards during the transient signOut → signIn window
    ref.read(isSwitchingAccountProvider.notifier).state = true;

    if (currentUid != null && currentUid.isNotEmpty) {
      try {
        await removeCurrentDeviceTokenForUser(
          ref.read(firestoreProvider),
          currentUid,
        );
      } catch (_) {}
    }

    final success = await manager.switchAccount(target.uid);

    // Clear the flag regardless of outcome
    ref.read(isSwitchingAccountProvider.notifier).state = false;

    if (!success) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not switch account. Please log in again.',
            ),
          ),
        );
      }
      return;
    }

    invalidateUserScopedProviders(container);
    container.invalidate(profileControllerProvider);
    container.invalidate(userBoomerangsControllerProvider);
    container.invalidate(storedAccountsProvider);

    if (context.mounted) {
      goRouter.go(HomeShell.routeName);
    }
  }

  /// Shows a bottom sheet prompting the user to enter their password
  /// for an account that was migrated without stored credentials.
  Future<void> _showReLoginSheet(
    BuildContext context,
    UserSession target,
  ) async {
    final passwordController = TextEditingController();
    final theme = Theme.of(context);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 20.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter password',
                  style: theme.textTheme.titleMedium,
                ),
                SizedBox(height: 4.h),
                Text(
                  target.email,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                SizedBox(height: 16.h),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Password',
                    filled: true,
                    fillColor: theme.colorScheme.onSurface
                        .withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) {
                    Navigator.of(sheetCtx).pop();
                    _performReLogin(context, target, passwordController.text);
                  },
                ),
                SizedBox(height: 12.h),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                    ),
                    onPressed: () {
                      Navigator.of(sheetCtx).pop();
                      _performReLogin(
                          context, target, passwordController.text);
                    },
                    child: const Text('Sign In'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _performReLogin(
    BuildContext context,
    UserSession target,
    String password,
  ) async {
    if (password.isEmpty) return;

    final container = ProviderScope.containerOf(context, listen: false);
    final goRouter = GoRouter.of(context);

    // Snapshot current user before switching
    final prevUser = ref.read(firebaseAuthProvider).currentUser;
    final prevProfile = ref.read(currentUserProfileProvider).value;
    UserSession? prevSession;
    if (prevUser != null) {
      prevSession = UserSession(
        uid: prevUser.uid,
        email: prevProfile?.email ?? prevUser.email ?? '',
        displayName: prevProfile?.fullName.isNotEmpty == true
            ? prevProfile!.fullName
            : prevProfile?.nickname ?? prevUser.displayName ?? '',
        photoUrl: prevProfile?.avatarUrl ?? prevUser.photoURL,
        lastLogin: DateTime.now(),
      );
    }

    await ref.read(authControllerProvider.notifier).login(
          target.email,
          password,
          previousAccount: prevSession,
        );

    if (!context.mounted) return;
    final next = ref.read(authStateProvider).asData?.value;
    if (next != null) {
      invalidateUserScopedProviders(container);
      container.invalidate(profileControllerProvider);
      container.invalidate(userBoomerangsControllerProvider);
      container.invalidate(storedAccountsProvider);
      goRouter.go(HomeShell.routeName);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect password.')),
      );
    }
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.displayName,
    required this.subtitle,
    this.photoUrl,
    required this.isActive,
    required this.onTap,
  });

  final String displayName;
  final String subtitle;
  final String? photoUrl;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 20.w),
      leading: AppAvatar(url: photoUrl, size: 48.r),
      title: Text(
        displayName.isNotEmpty ? displayName : 'User',
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isActive
          ? Icon(
              Icons.check_circle,
              color: theme.colorScheme.primary,
              size: 24.r,
            )
          : null,
      onTap: onTap,
    );
  }
}
