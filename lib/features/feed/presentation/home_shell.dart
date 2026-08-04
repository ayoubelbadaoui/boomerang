import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'tabs/home_tab.dart';
import 'tabs/discover_tab.dart';
import 'tabs/create_tab.dart';
import 'tabs/notifications_page.dart';
import '../../profile/presentation/profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/chat/presentation/pages/conversations_page.dart';
import 'package:boomerang/features/chat/application/chat_providers.dart';
import 'package:boomerang/features/feed/infrastructure/gallery_video_ingestor.dart';
import 'package:boomerang/features/feed/presentation/editor/gallery_import_flow.dart';
import 'package:boomerang/features/feed/presentation/widgets/upload_progress_bar.dart';
import 'package:boomerang/features/feed/presentation/camera/boomerang_camera_page.dart';
import 'package:boomerang/core/navigation/home_tab_navigation.dart';
import 'package:boomerang/core/navigation/notification_navigation.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  static const String routeName = '/home';

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  int _currentIndex = 0;

  // Guards against overlapping lost-data recoveries (e.g. several rapid
  // resume events) so a recovered video is only routed once.
  bool _recoveringLostVideo = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(homeTabIndexProvider, (_, next) {
      if (next != _currentIndex) {
        setState(() => _currentIndex = next);
      }
    });
    ref.listenManual(pendingNotificationNavProvider, (prev, next) {
      if (next == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _consumeNotificationIntent(next);
      });
    });
    WidgetsBinding.instance.addObserver(this);
    // The Activity may have just been recreated after being reclaimed while a
    // gallery picker was open — recover any dropped selection on first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recoverLostGalleryVideo();
      final pending = ref.read(pendingNotificationNavProvider);
      if (pending != null) _consumeNotificationIntent(pending);
    });
  }

  void _consumeNotificationIntent(NotificationNavIntent intent) {
    ref.read(pendingNotificationNavProvider.notifier).state = null;
    if (intent.kind == NotificationNavKind.activity) {
      _openNotifications();
    }
  }

  void _openNotifications() {
    final uid = ref.read(currentUserProfileProvider).value?.uid ?? '';
    if (uid.isNotEmpty) {
      ref.read(notificationsRepoProvider).markAllRead(uid: uid);
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsPage()),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recoverLostGalleryVideo();
    }
  }

  /// Recovers a gallery video that Android cached as "lost data" after the
  /// host Activity was destroyed while the picker was in the foreground.
  ///
  /// Without this, the original `pickVideo()` future is gone when the Activity
  /// is recreated, the picked clip is silently dropped, and the upload never
  /// starts — the post can't be published. Routing it back through the normal
  /// gallery flow drops the user straight onto the editor where they publish.
  Future<void> _recoverLostGalleryVideo() async {
    // Lost-data caching is Android-only; iOS returns an empty response.
    if (!Platform.isAndroid || _recoveringLostVideo || !mounted) return;
    _recoveringLostVideo = true;
    try {
      final lost = await ImagePicker().retrieveLostData();
      if (lost.isEmpty || lost.type != RetrieveType.video) return;
      final file = lost.file;
      if (file == null || !mounted) return;
      await presentGalleryVideo(context, file);
    } on GalleryVideoIngestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      // Best-effort recovery — never crash the shell over a dropped pick.
    } finally {
      _recoveringLostVideo = false;
    }
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
    final authState = ref.watch(authStateProvider);
    final user = authState.value;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final nicknameState = ref.watch(userHasNicknameProvider);
    if (nicknameState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (nicknameState.hasError) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load account data.'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  ref.invalidate(userHasNicknameProvider);
                  ref.invalidate(currentUserProfileProvider);
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final hasNickname = nicknameState.valueOrNull ?? false;
    if (!hasNickname) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar:
          _currentIndex == 0
              ? AppBar(
                centerTitle: true,
                elevation: 0,
                title: const Text('Home'),
                actions: [
                  _NotificationBell(onTap: _openNotifications),
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
                activeIcon: 'assets/bottom_navigation/active_light/home.svg',
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
              _ChatNavItem(active: _currentIndex == 3, onTap: () => _setTab(3)),
              _NavItem(
                label: 'Profile',
                active: _currentIndex == 4,
                activeIcon: 'assets/bottom_navigation/active_light/profile.svg',
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
        child: Center(child: Icon(Icons.add, size: 28.h, color: Colors.white)),
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
    final unread =
        uid.isEmpty ? 0 : ref.watch(unreadCountProvider(uid)).valueOrNull ?? 0;

    return IconButton(
      splashRadius: 24,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          SvgPicture.asset(
            'assets/svgs/notification.svg',
            height: 24.h,
            width: 24.h,
            colorFilter: const ColorFilter.mode(Colors.black, BlendMode.srcIn),
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
