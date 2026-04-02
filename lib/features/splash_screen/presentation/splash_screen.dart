import 'package:boomerang/core/assets/shared_assets.dart';
import 'package:boomerang/core/utils/image_precache.dart';
import 'package:boomerang/features/auth/presentation/onboarding_page.dart';
import 'package:boomerang/features/feed/presentation/home_shell.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  static const String routeName = '/';

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _navigated = false;
  bool _minDelayPassed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _warmPreviews();
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        _minDelayPassed = true;
        _tryNavigate();
      });
    });
  }

  Future<void> _warmPreviews() async {
    try {
      final repo = ref.read(boomerangRepoProvider);
      final snap = await repo.fetchBoomerangsPage(limit: 6);
      final urls = <String>[];
      for (final d in snap.docs) {
        final data = d.data();
        final u = data['imageUrl'];
        if (u is String && u.isNotEmpty) urls.add(u);
      }
      if (!mounted || urls.isEmpty) return;
      precacheImages(urls, context, concurrency: 2, cacheWidth: 400)
          .timeout(const Duration(seconds: 5), onTimeout: () {});
    } catch (_) {}
  }

  void _tryNavigate() {
    if (_navigated || !mounted || !_minDelayPassed) return;
    final auth = ref.read(authStateProvider);
    if (auth.isLoading) return;
    _navigated = true;
    auth.when(
      data: (user) => context.go(
        user != null ? HomeShell.routeName : OnboardingPage.routeName,
      ),
      error: (_, __) => context.go(OnboardingPage.routeName),
      loading: () {},
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authStateProvider, (_, __) => _tryNavigate());
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Image.asset(Assets.logoDark, cacheWidth: 240),
      ),
    );
  }
}
