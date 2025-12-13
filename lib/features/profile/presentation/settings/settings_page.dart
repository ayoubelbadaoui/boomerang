import 'package:boomerang/features/profile/application/settings_controller.dart';
import 'package:boomerang/features/profile/presentation/settings/manage_account_page.dart';
import 'package:boomerang/features/profile/presentation/settings/privacy_page.dart';
import 'package:boomerang/features/profile/presentation/settings/security_page.dart';
import 'package:boomerang/features/profile/presentation/settings/language_page.dart';
import 'package:boomerang/features/profile/presentation/settings/qr_code_page.dart';
import 'package:boomerang/features/profile/presentation/settings/help_center_page.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:boomerang/features/auth/presentation/onboarding_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
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
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Failed to load settings')),
        data:
            (s) => ListView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 32.h),
              children: [
                _Section(
                  title: 'Manage Account',
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ManageAccountPage(),
                        ),
                      ),
                ),
                _Section(
                  title: 'Privacy',
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PrivacyPage()),
                      ),
                ),
                _Section(
                  title: 'Security',
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SecurityPage()),
                      ),
                ),
                _Section(
                  title: 'QR Code',
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const QRCodePage()),
                      ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Language'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_langLabel(s.languageCode)),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LanguagePage()),
                      ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dark Mode'),
                  value: s.darkMode,
                  onChanged:
                      (v) => ref
                          .read(settingsControllerProvider.notifier)
                          .setBool('darkMode', v),
                ),
                const Divider(height: 24),
                _Section(title: 'Content Preferences', onTap: () {}),
                _Section(title: 'Ads', onTap: () {}),
                _Section(title: 'Report a Problem', onTap: () {}),
                _Section(
                  title: 'Help Center',
                  onTap:
                      () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const HelpCenterPage(),
                        ),
                      ),
                ),
                _Section(title: 'Safety Center', onTap: () {}),
                _Section(title: 'Community Guidelines', onTap: () {}),
                _Section(title: 'Terms of Services', onTap: () {}),
                _Section(title: 'Privacy Policy', onTap: () {}),
                SizedBox(height: 16.h),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Logout',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () async {
                    await ref.read(authControllerProvider.notifier).logout();
                    if (!context.mounted) return;
                    context.go(OnboardingPage.routeName);
                  },
                ),
              ],
            ),
      ),
    );
  }

  String _langLabel(String code) {
    switch (code) {
      case 'en_US':
        return 'English (US)';
      case 'en_GB':
        return 'English (UK)';
      default:
        return code;
    }
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.onTap});
  final String title;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
