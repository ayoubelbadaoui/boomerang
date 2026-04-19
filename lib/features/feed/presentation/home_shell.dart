import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'tabs/home_tab.dart';
import 'tabs/discover_tab.dart';
import 'tabs/create_tab.dart';
import 'tabs/inbox_tab.dart';
import '../../profile/presentation/profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/auth/presentation/setup_flow_page.dart';
import 'package:boomerang/features/auth/presentation/onboarding_page.dart';
import 'package:boomerang/features/chat/presentation/pages/conversations_page.dart';
import 'package:boomerang/features/chat/application/chat_providers.dart';
import 'package:boomerang/features/feed/presentation/widgets/upload_progress_bar.dart';
import 'package:boomerang/features/feed/presentation/camera/boomerang_camera_page.dart';
import 'package:go_router/go_router.dart';

final homeTabIndexProvider = StateProvider<int>((ref) => 0);

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  static const String routeName = '/home';

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    ref.listenManual(homeTabIndexProvider, (_, next) {
      if (next != _currentIndex) {
        setState(() => _currentIndex = next);
      }
    });
  }

  static final List<Widget> _tabs = <Widget>[
    const HomeTab(),
    const DiscoverTab(),
    const CreateTab(),
    const ConversationsPage(),
    const ProfileTab(),
  ];

  void _setTab(int index) {
    setState(() => _currentIndex = index);
    ref.read(homeTabIndexProvider.notifier).state = index;
  }

  @override
  Widget build(BuildContext context) {
    final isSwitching = ref.watch(isSwitchingAccountProvider);
    final authState = ref.watch(authStateProvider);
    final user = authState.value;
    if (authState.hasValue && user == null && !isSwitching) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(OnboardingPage.routeName);
      });
      return const Scaffold();
    }
    if (user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final nicknameState = ref.watch(userHasNicknameProvider);
    if (nicknameState.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final hasNickname = nicknameState.asData?.value ?? false;
    if (!hasNickname) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(SetupFlowPage.routeName);
      });
      return const Scaffold();
    }
    return Scaffold(
          appBar:
              _currentIndex == 0
                  ? AppBar(
                    centerTitle: true,
                    elevation: 0,
                    title: const Text('Home'),
                    actions: [
                      _NotificationBell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const InboxTab()),
                          );
                        },
                      ),
                    ],
                  )
                  : null,
          body: Column(
            children: [
              const UploadProgressBar(),
              Expanded(child: _tabs[_currentIndex]),
            ],
          ),

          bottomNavigationBar: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 4.h,
              top: 8.h,
            ),
            child: SizedBox(
              height: 72.h,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _NavItem(
                    label: 'Home',
                    active: _currentIndex == 0,
                    activeIcon:
                        'assets/bottom_navigation/active_light/home.svg',
                    inactiveIcon:
                        'assets/bottom_navigation/inactive_light/home.svg',
                    onTap: () => _setTab(0),
                  ),
                  _NavItem(
                    label: 'Discover',
                    active: _currentIndex == 1,
                    activeIcon:
                        'assets/bottom_navigation/active_light/discover.svg',
                    inactiveIcon:
                        'assets/bottom_navigation/inactive_light/discover.svg',
                    onTap: () => _setTab(1),
                  ),
                  _CreateButton(
                    active: _currentIndex == 2,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const BoomerangCameraPage(),
                        ),
                      );
                    },
                  ),
                  _ChatNavItem(
                    active: _currentIndex == 3,
                    onTap: () => _setTab(3),
                  ),
                  _NavItem(
                    label: 'Profile',
                    active: _currentIndex == 4,
                    activeIcon:
                        'assets/bottom_navigation/active_light/profile.svg',
                    inactiveIcon:
                        'assets/bottom_navigation/inactive_light/profile.svg',
                    onTap: () => _setTab(4),
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
    this.activeIcon = '',
    this.inactiveIcon = '',
    required this.onTap,
  });

  final String label;
  final bool active;
  final String activeIcon;
  final String inactiveIcon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double iconSize = 28.h; // uniform size for active/inactive icons
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: iconSize,
        height: iconSize,
        child: SvgPicture.asset(
          active ? activeIcon : inactiveIcon,
          fit: BoxFit.contain,
          colorFilter: null,
        ),
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
          child: Icon(Icons.add, size: 28.h, color: Colors.white),
        ),
      ),
    );
  }
}

class _NotificationBell extends ConsumerWidget {
  const _NotificationBell({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserProfileProvider).value?.uid ?? '';
    final unread = uid.isEmpty
        ? 0
        : ref.watch(unreadCountProvider(uid)).valueOrNull ?? 0;

    return IconButton(
      splashRadius: 24,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          SvgPicture.asset(
            'assets/svgs/notification.svg',
            height: 24.h,
            width: 24.h,
            colorFilter: const ColorFilter.mode(
              Colors.black,
              BlendMode.srcIn,
            ),
          ),
          if (unread > 0)
            Positioned(
              right: -4.w,
              top: -4.h,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.h),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(8.r),
                ),
                constraints: BoxConstraints(minWidth: 16.w, minHeight: 16.w),
                child: Center(
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      onPressed: () {
        if (uid.isNotEmpty) {
          ref.read(notificationsRepoProvider).markAllRead(uid: uid);
        }
        onTap();
      },
    );
  }
}

class _ChatNavItem extends ConsumerWidget {
  const _ChatNavItem({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(totalUnreadProvider);
    final double iconSize = 28.h;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: iconSize + 12.w,
        height: iconSize + 8.h,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: SizedBox(
                width: iconSize,
                height: iconSize,
                child: SvgPicture.asset(
                  active
                      ? 'assets/bottom_navigation/active_light/chat.svg'
                      : 'assets/bottom_navigation/inactive_light/chat.svg',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            if (unread > 0)
              Positioned(
                right: 0,
                top: -2.h,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.h),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  constraints: BoxConstraints(minWidth: 16.w, minHeight: 16.w),
                  child: Center(
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
