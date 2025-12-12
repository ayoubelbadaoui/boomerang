import 'package:boomerang/features/profile/application/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class PrivacyPage extends ConsumerWidget {
  const PrivacyPage({super.key});
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
          'Privacy',
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
                  'Discoverability',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18.sp,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Private Account'),
                  value: st.privateAccount,
                  onChanged:
                      (v) => ref
                          .read(settingsControllerProvider.notifier)
                          .setBool('privateAccount', v),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Suggest Account to Others'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sync Contacts & Friends'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap:
                      () => ref
                          .read(settingsControllerProvider.notifier)
                          .setBool('syncContacts', !st.syncContacts),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Loation Services'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap:
                      () => ref
                          .read(settingsControllerProvider.notifier)
                          .setBool('locationServices', !st.locationServices),
                ),
                SizedBox(height: 12.h),
                Text(
                  'Personalization',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18.sp,
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ads Personalization'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {},
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Quick Upload'),
                  value: st.quickUpload,
                  onChanged:
                      (v) => ref
                          .read(settingsControllerProvider.notifier)
                          .setBool('quickUpload', v),
                ),
                SizedBox(height: 12.h),
                Text(
                  'Safety',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18.sp,
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Downloads'),
                  trailing: const Icon(Icons.chevron_right),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Comments'),
                  trailing: const Icon(Icons.chevron_right),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mentions & Tags'),
                  trailing: const Icon(Icons.chevron_right),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Following List'),
                  trailing: const Icon(Icons.chevron_right),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Duet'),
                  trailing: const Icon(Icons.chevron_right),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Liked Video'),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ],
            ),
      ),
    );
  }
}






