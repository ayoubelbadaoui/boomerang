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
    // Defer to build to avoid ref.listen restriction
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
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
