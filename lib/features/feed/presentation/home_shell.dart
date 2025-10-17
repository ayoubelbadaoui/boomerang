import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'tabs/home_tab.dart';
import 'tabs/discover_tab.dart';
import 'tabs/create_tab.dart';
import 'tabs/inbox_tab.dart';
import 'tabs/profile_tab.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boomerang/infrastructure/providers.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  static const String routeName = '/home';

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  static final List<Widget> _tabs = <Widget>[
    const HomeTab(),
    const DiscoverTab(),
    const CreateTab(),
    const InboxTab(),
    const ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          _currentIndex == 0
              ? AppBar(
                centerTitle: true,
                elevation: 0,
                title: const Text('Home'),
                actions: [
                  Consumer(
                    builder:
                        (context, ref, _) => Padding(
                          padding: EdgeInsets.only(right: 8.w),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: () async {
                              await ref
                                  .read(boomerangRepoProvider)
                                  .addRandomBoomerang();
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Random boomerang added'),
                                ),
                              );
                            },
                            child: Container(
                              padding: EdgeInsets.all(10.w),
                              decoration: const BoxDecoration(
                                color: Colors.black,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.bolt,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                  ),
                ],
              )
              : null,
      body: _tabs[_currentIndex],

      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(bottom: 8.h, top: 8.h),
        child: SizedBox(
          height: 72.h,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _NavItem(
                label: 'Home',
                active: _currentIndex == 0,
                activeIcon: 'assets/bottom_navigation/active_light/home.svg',
                inactiveIcon:
                    'assets/bottom_navigation/inactive_light/home.svg',
                onTap: () => setState(() => _currentIndex = 0),
              ),
              _NavItem(
                label: 'Discover',
                active: _currentIndex == 1,
                activeIcon:
                    'assets/bottom_navigation/active_light/discover.svg',
                inactiveIcon:
                    'assets/bottom_navigation/inactive_light/discover.svg',
                onTap: () => setState(() => _currentIndex = 1),
              ),
              _CreateButton(
                active: _currentIndex == 2,
                onTap: () => setState(() => _currentIndex = 2),
              ),
              _NavItem(
                label: 'Inbox',
                active: _currentIndex == 3,
                activeIcon: 'assets/bottom_navigation/active_light/chat.svg',
                inactiveIcon:
                    'assets/bottom_navigation/inactive_light/chat.svg',
                onTap: () => setState(() => _currentIndex = 3),
              ),
              _NavItem(
                label: 'Profile',
                active: _currentIndex == 4,
                activeIcon: 'assets/bottom_navigation/active_light/profile.svg',
                inactiveIcon:
                    'assets/bottom_navigation/inactive_light/profile.svg',
                onTap: () => setState(() => _currentIndex = 4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Removed placeholder widget; tabs now use dedicated screens

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.active,
    required this.activeIcon,
    required this.inactiveIcon,
    required this.onTap,
  });

  final String label;
  final bool active;
  final String activeIcon;
  final String inactiveIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.black : Colors.grey;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            active ? activeIcon : inactiveIcon,
            height: 24.h,
            width: 24.h,
            colorFilter: null,
          ),
          SizedBox(height: 6.h),
          Text(label, style: TextStyle(fontSize: 12.sp, color: color)),
        ],
      ),
    );
  }
}

class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56.h,
        width: 56.h,
        decoration: BoxDecoration(color: Colors.black, shape: BoxShape.circle),
        child: Center(
          child: SvgPicture.asset(
            'assets/bottom_navigation/flash.svg',
            height: 24.h,
            width: 24.h,
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }
}
