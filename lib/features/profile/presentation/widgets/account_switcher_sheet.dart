import 'package:boomerang/core/auth/user_session.dart';
import 'package:boomerang/core/widgets/avatar.dart';
import 'package:boomerang/features/auth/presentation/login_page.dart';
import 'package:boomerang/features/feed/presentation/home_shell.dart';
import 'package:boomerang/features/profile/application/account_switch_controller.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

/// Instagram-style account switcher presented as a modal bottom sheet.
///
/// Captures a stable [ProviderContainer] and [GoRouter] from the calling
/// page's context **before** any sheet is opened, so all follow-up logic
/// (password prompt, provider invalidation, navigation) stays safe even
/// after the switcher is dismissed.
Future<void> showAccountSwitcher(BuildContext context, WidgetRef ref) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final goRouter = GoRouter.of(context);
  final controller = AccountSwitchController(container);

  ref.invalidate(storedAccountsProvider);
  await controller.ensureCurrentAccountStored();

  if (!context.mounted) return;

  // Show the account list — returns the selected UserSession or null.
  final result = await showModalBottomSheet<UserSession?>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
    ),
    builder: (_) => _AccountSwitcherBody(
      onAddAccount: () => goRouter.push(LoginPage.routeName),
    ),
  );

  if (result == null || !context.mounted) return;

  // If no stored credentials for the target account, prompt for password.
  String? password;
  if (!await controller.hasCredentials(result.uid)) {
    if (!context.mounted) return;
    password = await _showPasswordSheet(context, result);
    if (password == null || password.isEmpty || !context.mounted) return;
  }

  // Loading feedback while the switch is in progress
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    const SnackBar(
      content: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          SizedBox(width: 12),
          Text('Switching account\u2026'),
        ],
      ),
      duration: Duration(seconds: 30),
    ),
  );

  final success = await controller.switchTo(result, password: password);
  messenger.hideCurrentSnackBar();

  if (success) {
    goRouter.go(HomeShell.routeName);
  } else if (context.mounted) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Could not switch account. Please log in again.'),
      ),
    );
  }
}

/// Bottom sheet that prompts for a password and returns the entered text.
Future<String?> _showPasswordSheet(
  BuildContext context,
  UserSession target,
) {
  final passwordController = TextEditingController();
  final theme = Theme.of(context);

  return showModalBottomSheet<String>(
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
              Text('Enter password', style: theme.textTheme.titleMedium),
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
                  fillColor:
                      theme.colorScheme.onSurface.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) {
                  Navigator.of(sheetCtx).pop(passwordController.text);
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
                    Navigator.of(sheetCtx).pop(passwordController.text);
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

// ---------------------------------------------------------------------------
// Switcher body — pure presentation; returns UserSession on selection
// ---------------------------------------------------------------------------

class _AccountSwitcherBody extends ConsumerWidget {
  const _AccountSwitcherBody({required this.onAddAccount});

  final VoidCallback onAddAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final storedAccounts =
        ref.watch(storedAccountsProvider).valueOrNull ?? [];
    final currentProfile = ref.watch(currentUserProfileProvider).value;
    final currentUid = ref.watch(firebaseAuthProvider).currentUser?.uid;

    final otherAccounts =
        storedAccounts.where((a) => a.uid != currentUid).toList();

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
                child: Text('Accounts', style: theme.textTheme.titleLarge),
              ),
            ),
            SizedBox(height: 12.h),

            // Current user — tapping just dismisses the sheet
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

            // Other stored accounts — tapping returns the selected session
            for (final account in otherAccounts)
              _AccountTile(
                displayName: account.displayName,
                subtitle: account.email,
                photoUrl: account.photoUrl,
                isActive: false,
                onTap: () => Navigator.of(context).pop(account),
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
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.2),
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
                onAddAccount();
              },
            ),
          ],
        ),
      ),
    );
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
