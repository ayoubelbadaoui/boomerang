import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'auth_choice_page.dart';

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  static const String routeName = '/onboarding';

  @override
  Widget build(BuildContext context) {
    final pageController = PageController();
    final pages = _OnboardingItem.pages;

    return Scaffold(
      body: Stack(
        children: [
          PageView.builder(
            controller: pageController,
            physics: const BouncingScrollPhysics(),
            itemCount: pages.length,
            itemBuilder: (context, index) {
              final item = pages[index];
              return _OnboardingSlide(item: item);
            },
          ),
          // Bottom gradient overlay
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                height: 360.h,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54, Colors.black],
                  ),
                ),
              ),
            ),
          ),
          // Text + indicators + button
          Positioned(
            left: 24.w,
            right: 24.w,
            bottom: 48.h,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IgnorePointer(
                  ignoring: true,
                  child: AnimatedBuilder(
                    animation: pageController,
                    builder: (context, _) {
                      final index =
                          pageController.hasClients
                              ? (pageController.page ??
                                      pageController.initialPage.toDouble())
                                  .round()
                              : 0;
                      final item = pages[index];
                      return Text(
                        item.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 33.sp,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(height: 24.h),
                Center(
                  child: IgnorePointer(
                    ignoring: true,
                    child: SmoothPageIndicator(
                      controller: pageController,
                      count: pages.length,
                      effect: const ExpandingDotsEffect(
                        dotColor: Colors.white38,
                        activeDotColor: Colors.white,
                        dotHeight: 8,
                        dotWidth: 8,
                        expansionFactor: 2.2,
                        spacing: 8,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 24.h),
                Align(
                  alignment: Alignment.center,
                  child: AnimatedBuilder(
                    animation: pageController,
                    builder: (context, _) {
                      final currentIndex =
                          pageController.hasClients
                              ? (pageController.page ?? 0).round()
                              : 0;
                      final isLast = currentIndex >= pages.length - 1;
                      return _PrimaryBottomButton(
                        label: isLast ? 'Get Started' : 'Next',
                        onPressed: () async {
                          if (!pageController.hasClients) return;
                          if (isLast) {
                            context.push(AuthChoicePage.routeName);
                          } else {
                            await pageController.nextPage(
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeOut,
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          // Skip button top-right
          Positioned(
            top: MediaQuery.of(context).padding.top + 12.h,
            right: 16.w,
            child: TextButton(
              onPressed: () => context.push(AuthChoicePage.routeName),
              child: const Text('Skip'),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({required this.item});

  final _OnboardingItem item;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background image
        Image.asset(item.imageAsset, fit: BoxFit.cover),
      ],
    );
  }
}

class _PrimaryBottomButton extends StatelessWidget {
  const _PrimaryBottomButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        shape: const StadiumBorder(),
        padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 16.h),
        elevation: 0,
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _OnboardingItem {
  const _OnboardingItem({required this.title, required this.imageAsset});

  final String title;
  final String imageAsset;

  static List<_OnboardingItem> get pages => const [
    _OnboardingItem(
      title: 'Watch interesting\nboomerangs from\naround the world',
      imageAsset: 'assets/onboarding/1.png',
    ),
    _OnboardingItem(
      title: 'Find your friends and\nplay together on\nsocial media',
      imageAsset: 'assets/onboarding/2.png',
    ),
    _OnboardingItem(
      title: "Let's have fun with\nyour friends right\nnow!",
      imageAsset: 'assets/onboarding/3.png',
    ),
  ];
}
