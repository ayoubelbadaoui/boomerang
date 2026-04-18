import 'package:boomerang/features/profile/application/profile_controller.dart';
import 'package:boomerang/features/profile/application/user_boomerangs_controller.dart';
import 'package:boomerang/features/profile/presentation/settings/manage_account_page.dart';
import 'package:boomerang/features/profile/presentation/settings/notifications_page.dart';
import 'package:boomerang/features/profile/presentation/settings/privacy_page.dart';
import 'package:boomerang/core/notifications/push_notifications_service.dart';
import 'package:boomerang/features/feed/presentation/home_shell.dart';
import 'package:boomerang/features/legal/presentation/legal_page.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:boomerang/features/auth/presentation/onboarding_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});
  static const String routeName = '/settings';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: Text(
          'Settings',
          style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 40.h),
        children: [
          _SettingsGroup(
            children: [
              _SettingsTile(
                icon: Icons.person_outline_rounded,
                title: 'Account',
                subtitle: 'Profile, email, phone, password',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ManageAccountPage(),
                  ),
                ),
              ),
              _SettingsTile(
                icon: Icons.lock_outline_rounded,
                title: 'Privacy',
                subtitle: 'Visibility, data, personalization',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PrivacyPage()),
                ),
              ),
              _SettingsTile(
                icon: Icons.notifications_none_rounded,
                title: 'Notifications',
                subtitle: 'Push alerts, sounds, preferences',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const NotificationsPage(),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 24.h),
          _SettingsGroup(
            children: [
              _SettingsTile(
                icon: Icons.help_outline_rounded,
                title: 'Help & Support',
                onTap: () => showCommunityGuidelines(context),
              ),
              _SettingsTile(
                icon: Icons.description_outlined,
                title: 'Terms & Privacy Policy',
                onTap: () => _showLegalSheet(context),
              ),
            ],
          ),
          SizedBox(height: 32.h),
          _LogoutButton(onTap: () => _confirmLogout(context, ref)),
          SizedBox(height: 24.h),
          Center(
            child: Text(
              'Boomerang v1.0',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 12.sp,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _showLegalSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            SizedBox(height: 16.h),
            ListTile(
              leading: const Icon(Icons.gavel_rounded),
              title: const Text('Terms of Service'),
              onTap: () {
                Navigator.pop(ctx);
                showTermsOfService(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Privacy Policy'),
              onTap: () {
                Navigator.pop(ctx);
                showPrivacyPolicy(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.people_outline_rounded),
              title: const Text('Community Guidelines'),
              onTap: () {
                Navigator.pop(ctx);
                showCommunityGuidelines(context);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                height: 1,
                indent: 56.w,
                color: Colors.grey.shade200,
              ),
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
      leading: Container(
        width: 36.r,
        height: 36.r,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10.r),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 20.r, color: Colors.black87),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15.sp,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12.sp,
                color: Colors.grey.shade500,
              ),
            )
          : null,
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: Colors.grey.shade400,
      ),
      onTap: onTap,
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 16.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: Colors.red.shade200),
        ),
        alignment: Alignment.center,
        child: Text(
          'Log Out',
          style: TextStyle(
            color: Colors.red,
            fontSize: 16.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

Future<void> _performLogout(WidgetRef ref, ProviderContainer container) async {
  try {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      await removeCurrentDeviceTokenForUser(
        ref.read(firestoreProvider),
        uid,
      );
    }
  } catch (_) {}
  try {
    invalidateUserScopedProviders(container);
    container.invalidate(profileControllerProvider);
    container.invalidate(userBoomerangsControllerProvider);
    container.invalidate(storedAccountsProvider);
  } catch (_) {}
  try {
    await ref.read(authControllerProvider.notifier).logout();
  } catch (_) {}
}

void _confirmLogout(BuildContext navigatorContext, WidgetRef ref) {
  final theme = Theme.of(navigatorContext);
  final goRouter = GoRouter.of(navigatorContext);
  final container = ProviderScope.containerOf(navigatorContext, listen: false);

  showModalBottomSheet<void>(
    context: navigatorContext,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Logout',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Are you sure you want to log out?',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        Navigator.of(sheetContext).pop();
                        final manager = ref.read(multiAccountManagerProvider);
                        final uid =
                            ref.read(firebaseAuthProvider).currentUser?.uid;

                        if (uid != null) {
                          final next =
                              await manager.nextAccountAfterRemoval(uid);
                          await manager.removeAccount(uid);

                          if (next != null) {
                            await _performLogout(ref, container);
                            final ok =
                                await manager.switchAccount(next.uid);
                            container.invalidate(storedAccountsProvider);
                            if (ok) {
                              invalidateUserScopedProviders(container);
                              container.invalidate(profileControllerProvider);
                              container.invalidate(
                                userBoomerangsControllerProvider,
                              );
                              goRouter.go(HomeShell.routeName);
                              return;
                            }
                          }
                        }

                        await _performLogout(ref, container);
                        goRouter.go(OnboardingPage.routeName);
                      },
                      child: const Text('Logout'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
