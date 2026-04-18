import 'package:boomerang/features/profile/application/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

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
          'Notifications',
          style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.w800),
        ),
      ),
      body: settings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Failed to load settings')),
        data: (s) => ListView(
          padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 32.h),
          children: [
            _SectionHeader(title: 'Activity'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Likes'),
              subtitle: const Text('When someone likes your boomerang'),
              activeThumbColor: Colors.white,
              activeTrackColor: Colors.black,
              value: true,
              onChanged: (_) {},
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Comments'),
              subtitle: const Text('When someone comments on your post'),
              activeThumbColor: Colors.white,
              activeTrackColor: Colors.black,
              value: true,
              onChanged: (_) {},
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('New Followers'),
              subtitle: const Text('When someone starts following you'),
              activeThumbColor: Colors.white,
              activeTrackColor: Colors.black,
              value: true,
              onChanged: (_) {},
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mentions'),
              subtitle: const Text('When someone mentions you'),
              activeThumbColor: Colors.white,
              activeTrackColor: Colors.black,
              value: true,
              onChanged: (_) {},
            ),
            SizedBox(height: 16.h),
            _SectionHeader(title: 'Messages'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Direct Messages'),
              subtitle: const Text('When you receive a new message'),
              activeThumbColor: Colors.white,
              activeTrackColor: Colors.black,
              value: true,
              onChanged: (_) {},
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Group Messages'),
              subtitle: const Text('Messages in group chats'),
              activeThumbColor: Colors.white,
              activeTrackColor: Colors.black,
              value: true,
              onChanged: (_) {},
            ),
            SizedBox(height: 16.h),
            _SectionHeader(title: 'General'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sounds'),
              subtitle: const Text('Play sound for notifications'),
              activeThumbColor: Colors.white,
              activeTrackColor: Colors.black,
              value: true,
              onChanged: (_) {},
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Vibration'),
              subtitle: const Text('Vibrate for notifications'),
              activeThumbColor: Colors.white,
              activeTrackColor: Colors.black,
              value: true,
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 18.sp,
        ),
      ),
    );
  }
}
