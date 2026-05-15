import 'package:boomerang/core/assets/shared_assets.dart';
import 'package:boomerang/core/utils/image_precache.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';

/// First Flutter-side route. Acts as a hand-off between the native launch
/// screen and the actual app shell:
///  - Background matches the native launch image so the transition is
///    seamless (no "weird black screen" between the two splashes).
///  - No hardcoded delay — router redirects decide the next route once auth
///    and profile guards resolve. A small circular indicator under the logo
///    signals to the user that loading is still in progress.
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _warmPreviews();
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
      precacheImages(
        urls,
        context,
        concurrency: 2,
        cacheWidth: 400,
      ).timeout(const Duration(seconds: 5), onTimeout: () {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset(
          Assets.logoLight,
          width: 248,
          height: 248,
          fit: BoxFit.contain,
          cacheWidth: 496,
        ),
      ),
    );
  }
}
