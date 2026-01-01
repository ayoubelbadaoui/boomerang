import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'router.dart';
import 'core/notifications/push_notifications_service.dart';

class BoomerangApp extends ConsumerWidget {
  const BoomerangApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Activate push notifications bootstrapper
    ref.read(pushNotificationsProvider);
    return ScreenUtilInit(
      designSize: const Size(428, 926),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp.router(
          title: 'Boomerang',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            fontFamily: 'Urbanist',
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF111111),
            ),
            useMaterial3: true,
          ),
          routerConfig: router,
        );
      },
    );
  }
}
