import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:boomerang/core/notifications/in_app_notification.dart';
import 'package:boomerang/core/widgets/avatar.dart';
import 'package:boomerang/router.dart';

class InAppNotificationOverlay extends ConsumerStatefulWidget {
  const InAppNotificationOverlay({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<InAppNotificationOverlay> createState() =>
      _InAppNotificationOverlayState();
}

class _InAppNotificationOverlayState
    extends ConsumerState<InAppNotificationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<Offset> _slideAnimation;
  Timer? _autoDismiss;
  InAppNotification? _current;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 250),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeIn,
    ));
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _show(InAppNotification notif) {
    _autoDismiss?.cancel();
    setState(() => _current = notif);
    _animController.forward(from: 0);
    _autoDismiss = Timer(const Duration(seconds: 4), _dismiss);
  }

  Future<void> _dismiss() async {
    _autoDismiss?.cancel();
    await _animController.reverse();
    if (mounted) setState(() => _current = null);
  }

  void _onTap() {
    final convId = _current?.conversationId;
    _dismiss();
    if (convId != null && convId.isNotEmpty) {
      router.push('/chat/$convId');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<InAppNotification?>(inAppNotificationProvider, (prev, next) {
      if (next != null) {
        _show(next);
        Future.microtask(
          () => ref.read(inAppNotificationProvider.notifier).state = null,
        );
      }
    });

    final topPadding = MediaQuery.paddingOf(context).top;

    return Stack(
      children: [
        widget.child,
        if (_current != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SlideTransition(
              position: _slideAnimation,
              child: GestureDetector(
                onTap: _onTap,
                onVerticalDragEnd: (d) {
                  if (d.primaryVelocity != null && d.primaryVelocity! < -100) {
                    _dismiss();
                  }
                },
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    margin: EdgeInsets.fromLTRB(
                      10.w,
                      topPadding + 6.h,
                      10.w,
                      0,
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: 14.w,
                      vertical: 12.h,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xF0262626),
                      borderRadius: BorderRadius.circular(16.r),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        AppAvatar(
                          url: _current!.avatarUrl,
                          size: 40.r,
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _current!.title,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 2.h),
                              Text(
                                _current!.body,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13.sp,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          'now',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 12.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
