import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'router.dart';
import 'core/theme/app_theme.dart';
import 'core/notifications/push_notifications_service.dart';
import 'core/notifications/in_app_notification_overlay.dart';
import 'infrastructure/providers.dart';

class BoomerangApp extends ConsumerWidget {
  const BoomerangApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Log FFmpeg output to the console for easier diagnosis in TestFlight/dev.
    FFmpegKitConfig.enableLogCallback((log) {
      // ignore: avoid_print
      print('FFMPEG||logger: ${log.getMessage()}');
    });
    FFmpegKitConfig.enableStatisticsCallback((stats) {
      // ignore: avoid_print
      print(
        'FFMPEG||loggerSTATS: time=${stats.getTime()} size=${stats.getSize()} bitrate=${stats.getBitrate()} speed=${stats.getSpeed()}',
      );
    });

    // Activate push notifications bootstrapper
    ref.read(pushNotificationsProvider);
    // Keep boomerang privacy flags in sync with the current user's setting.
    ref.watch(privacyBackfillGuardProvider);
    return ScreenUtilInit(
      designSize: const Size(428, 926),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp.router(
          title: 'Boomerang',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          routerConfig: ref.watch(routerProvider),
          builder: (context, child) {
            return GestureDetector(
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              behavior: HitTestBehavior.translucent,
              child: InAppNotificationOverlay(child: child!),
            );
          },
        );
      },
    );
  }
}
