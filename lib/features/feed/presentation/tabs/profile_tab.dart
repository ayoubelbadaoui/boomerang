import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/auth/presentation/onboarding_page.dart';

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  static const String routeName = '/profile_tab';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () {},
          icon: const Icon(
            Icons.person_add_alt_1_outlined,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Andrew..',
              style: TextStyle(
                color: Colors.black,
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _showSettingsSheet(context, ref),
            icon: const Icon(Icons.settings_outlined, color: Colors.black),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 20.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: 8.h),
            Stack(
              children: [
                CircleAvatar(
                  radius: 48.r,
                  backgroundImage: const NetworkImage(
                    'https://i.pravatar.cc/200?img=12',
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 24.r,
                    width: 24.r,
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.edit,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            Text(
              '@andrew_ainsley',
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 6.h),
            Text(
              'Designer & Videographer',
              style: TextStyle(color: Colors.black54, fontSize: 14.sp),
            ),
            SizedBox(height: 20.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                _Stat(value: '247', label: 'Bmg.'),
                _Stat(value: '368K', label: 'Followers'),
                _Stat(value: '374', label: 'Following'),
                _Stat(value: '3.7M', label: 'Likes'),
              ],
            ),
            SizedBox(height: 16.h),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.black, width: 1),
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  shape: StadiumBorder(
                    side: BorderSide(color: Colors.black, width: 1.w),
                  ),
                ),
                icon: const Icon(Icons.circle, size: 10, color: Colors.black),
                label: Text(
                  'Edit Profile',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            SizedBox(height: 16.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: const [
                _ModeIcon(icon: Icons.grid_on_rounded, active: true),
                _ModeIcon(icon: Icons.bookmark_border_rounded),
                _ModeIcon(icon: Icons.favorite_border_rounded),
              ],
            ),
            SizedBox(height: 12.h),
            Divider(height: 1.h, color: Colors.black12),
            SizedBox(height: 12.h),
            _PostsGrid(),
            SizedBox(height: 80.h),
          ],
        ),
      ),
    );
  }
}

void _showSettingsSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(height: 16.h),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text(
                'Log out',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await ref.read(authControllerProvider.notifier).logout();
                if (context.mounted) {
                  context.go(OnboardingPage.routeName);
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    },
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 4.h),
        Text(label, style: TextStyle(fontSize: 12.sp, color: Colors.black54)),
      ],
    );
  }
}

class _ModeIcon extends StatelessWidget {
  const _ModeIcon({required this.icon, this.active = false});
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36.r,
      width: 36.r,
      decoration: BoxDecoration(
        color: active ? Colors.black : Colors.transparent,
        borderRadius: BorderRadius.circular(10.r),
        border: active ? null : Border.all(color: Colors.black12),
      ),
      child: Icon(
        icon,
        color: active ? Colors.white : Colors.black54,
        size: 18.r,
      ),
    );
  }
}

class _PostsGrid extends StatelessWidget {
  final List<String> _imgs = const [
    'https://picsum.photos/seed/p1/800/800',
    'https://picsum.photos/seed/p2/800/800',
    'https://picsum.photos/seed/p3/800/800',
    'https://picsum.photos/seed/p4/800/800',
    'https://picsum.photos/seed/p5/800/800',
    'https://picsum.photos/seed/p6/800/800',
    'https://picsum.photos/seed/p7/800/800',
    'https://picsum.photos/seed/p8/800/800',
    'https://picsum.photos/seed/p9/800/800',
  ];

  const _PostsGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: _imgs.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8.w,
        crossAxisSpacing: 8.w,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12.r),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                _imgs[index],
                fit: BoxFit.cover,
                errorBuilder:
                    (context, _, __) => Container(color: Colors.black12),
              ),
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.remove_red_eye,
                        size: 12,
                        color: Colors.white70,
                      ),
                      SizedBox(width: 4.w),
                      const Text(
                        '367.5K',
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
