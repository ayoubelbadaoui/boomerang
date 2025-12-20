import 'package:boomerang/core/assets/shared_assets.dart';
import 'package:boomerang/features/auth/presentation/onboarding_page.dart';
import 'package:boomerang/features/feed/presentation/home_shell.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  static const String routeName = '/';

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Warm up first-page previews; do not block navigation.
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmPreviews());
    // Defer to build to avoid ref.listen restriction
  }

  Future<void> _warmPreviews() async {
    try {
      final repo = ref.read(boomerangRepoProvider);
      final snap = await repo.fetchBoomerangsPage(limit: 24);
      final urls = <String>[];
      for (final d in snap.docs) {
        final data = d.data();
        final u = data['imageUrl'];
        if (u is String && u.isNotEmpty) urls.add(u);
      }
      if (!mounted || urls.isEmpty) return;
      // Kick off precache; don't await all.
      for (final u in urls) {
        // ignore: discarded_futures
        precacheImage(NetworkImage(u), context);
      }
    } catch (_) {
      // Ignore warmup failures
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    // wait 2 seconds and then navigate to the home screen
    Future.delayed(const Duration(seconds: 2), () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (auth.isLoading) return;
        auth.when(
          data:
              (user) => context.go(
                user != null ? HomeShell.routeName : OnboardingPage.routeName,
              ),
          error: (_, __) => context.go(OnboardingPage.routeName),
          loading: () {},
        );
      });
    });
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(Assets.logo),
            SizedBox(height: 16.h),
            CircularProgressIndicator(color: Colors.black),
          ],
        ),
      ),
    );
  }
}
