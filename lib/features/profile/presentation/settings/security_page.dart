import 'package:boomerang/features/profile/application/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class SecurityPage extends ConsumerWidget {
  const SecurityPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsControllerProvider);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: Text(
          'Security',
          style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.w800),
        ),
      ),
      body: s.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Failed to load settings')),
        data:
            (st) => ListView(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 32.h),
              children: [
                Text(
                  'Control',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18.sp,
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Security Alerts'),
                  trailing: const Icon(Icons.chevron_right),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Manage Devices'),
                  trailing: const Icon(Icons.chevron_right),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Manage Permission'),
                  trailing: const Icon(Icons.chevron_right),
                ),
                SizedBox(height: 12.h),
                Text(
                  'Security',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18.sp,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Remember me'),
                  value: st.adsPersonalization, // reuse for demo persistence
                  onChanged:
                      (v) => ref
                          .read(settingsControllerProvider.notifier)
                          .setBool('adsPersonalization', v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Face ID'),
                  value: false,
                  onChanged: (v) {},
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Biometric ID'),
                  value: true,
                  onChanged: (v) {},
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Google Authenticator'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                SizedBox(height: 16.h),
                OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16.h),
                    shape: StadiumBorder(
                      side: BorderSide(color: Colors.black, width: 1.w),
                    ),
                  ),
                  child: const Text('Change PIN'),
                ),
                SizedBox(height: 12.h),
                OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16.h),
                    shape: StadiumBorder(
                      side: BorderSide(color: Colors.black12, width: 1),
                    ),
                    foregroundColor: Colors.black54,
                  ),
                  child: const Text('Change Password'),
                ),
              ],
            ),
      ),
    );
  }
}








