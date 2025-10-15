import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/auth/presentation/signup_page.dart';
import 'features/feed/presentation/home_shell.dart';
import 'features/auth/presentation/onboarding_page.dart';
import 'infrastructure/providers.dart';

final router = GoRouter(
  initialLocation: OnboardingPage.routeName,
  routes: [
    GoRoute(
      path: OnboardingPage.routeName,
      builder: (c, s) => const OnboardingPage(),
    ),
    GoRoute(path: LoginPage.routeName, builder: (c, s) => const LoginPage()),
    GoRoute(path: SignupPage.routeName, builder: (c, s) => const SignupPage()),
    GoRoute(path: HomeShell.routeName, builder: (c, s) => const HomeShell()),
  ],
  redirect: (context, state) {
    final container = ProviderScope.containerOf(context, listen: false);
    final auth = container.read(authStateProvider);
    final loggingIn =
        state.fullPath == LoginPage.routeName ||
        state.fullPath == SignupPage.routeName;

    if (auth.asData == null) return null; // wait until first frame resolves
    final user = auth.asData!.value;
    if (user == null && !loggingIn) return OnboardingPage.routeName;
    if (user != null &&
        (state.fullPath == LoginPage.routeName ||
            state.fullPath == SignupPage.routeName)) {
      return HomeShell.routeName;
    }
    return null;
  },
);
