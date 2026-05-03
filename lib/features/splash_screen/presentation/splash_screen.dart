import 'package:boomerang/core/assets/shared_assets.dart';
import 'package:boomerang/core/utils/image_precache.dart';
import 'package:boomerang/features/auth/presentation/onboarding_page.dart';
import 'package:boomerang/features/feed/presentation/home_shell.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// First Flutter-side route. Acts as a hand-off between the native launch
/// screen and the actual app shell:
///  - Background matches the native launch image so the transition is
///    seamless (no "weird black screen" between the two splashes).
///  - No hardcoded delay — we navigate as soon as the auth stream resolves
///    its first value. A small circular indicator under the logo signals
///    to the user that loading is still in progress.
///  - Image prefetch for the first few posts runs in the background so the
///    feed paints faster once the user arrives at it, but it never blocks
///    navigation.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  static const String routeName = '/';

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _warmPreviews();
      _tryNavigate();
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
    if (_navigated || !mounted) return;
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
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // `logoLight` is the black-on-transparent version of the logo,
            // designed for light surfaces. Using `logoDark` (white logo)
            // here would render invisible on the white background.
            Image.asset(Assets.logoLight, cacheWidth: 240),
            const SizedBox(height: 24),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
