import 'package:boomerang/features/splash_screen/presentation/splash_screen.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/auth/presentation/signup_page.dart';
import 'features/feed/presentation/home_shell.dart';
import 'features/auth/presentation/onboarding_page.dart';
import 'features/auth/presentation/auth_choice_page.dart';
import 'features/auth/presentation/setup_profile_page.dart';
import 'features/auth/presentation/setup_flow_page.dart';
import 'features/auth/presentation/choose_username_page.dart';
import 'infrastructure/providers.dart';

final router = GoRouter(
  initialLocation: SplashScreen.routeName,

  routes: [
    GoRoute(
      path: SplashScreen.routeName,
      builder: (c, s) => const SplashScreen(),
    ),
    GoRoute(
      path: OnboardingPage.routeName,
      builder: (c, s) => const OnboardingPage(),
    ),
    GoRoute(
      path: AuthChoicePage.routeName,
      builder: (c, s) => const AuthChoicePage(),
    ),
    GoRoute(path: LoginPage.routeName, builder: (c, s) => const LoginPage()),
    GoRoute(path: SignupPage.routeName, builder: (c, s) => const SignupPage()),
    GoRoute(
      path: SetupProfilePage.routeName,
      builder: (c, s) => const SetupProfilePage(),
    ),
    GoRoute(
      path: SetupFlowPage.routeName,
      builder: (c, s) => const SetupFlowPage(),
    ),
    GoRoute(
      path: ChooseUsernamePage.routeName,
      builder: (c, s) => const ChooseUsernamePage(),
    ),
    GoRoute(path: HomeShell.routeName, builder: (c, s) => const HomeShell()),
  ],
  redirect: (context, state) {
    final container = ProviderScope.containerOf(context, listen: false);
    final auth = container.read(authStateProvider);
    final profileExists = container.read(userProfileExistsProvider);
    final profileComplete = container.read(userProfileCompleteProvider);
    final hasUsername = container.read(userHasUsernameProvider);
    final isAuthChoice = state.fullPath == AuthChoicePage.routeName;
    final isLogin = state.fullPath == LoginPage.routeName;
    final isSignup = state.fullPath == SignupPage.routeName;
    final isOnboarding = state.fullPath == OnboardingPage.routeName;
    final isSetupFlow = state.fullPath == SetupFlowPage.routeName;
    final isChooseUsername = state.fullPath == ChooseUsernamePage.routeName;

    if (auth.asData == null) return null; // wait until first frame resolves
    final user = auth.asData!.value;

    if (user == null) {
      // Allow auth/setup flow routes; otherwise push to onboarding
      final isAuthFlow =
          isOnboarding || isAuthChoice || isLogin || isSignup || isSetupFlow;
      return isAuthFlow ? null : OnboardingPage.routeName;
    }

    // User signed in: wait for username/profile checks
    if (hasUsername.asData == null ||
        profileExists.asData == null ||
        profileComplete.asData == null) {
      return null; // wait checks
    }
    final hasName = hasUsername.asData!.value;
    if (!hasName && !isChooseUsername) return ChooseUsernamePage.routeName;
    if (hasName && isChooseUsername) return HomeShell.routeName;
    final hasProfile = profileExists.asData!.value;
    final isComplete = profileComplete.asData!.value;
    if (hasProfile && isComplete && isOnboarding) return HomeShell.routeName;
    if (hasProfile &&
        !isComplete &&
        state.fullPath != SetupFlowPage.routeName) {
      return SetupFlowPage.routeName;
    }
    // allow navigation in auth/setup flow otherwise
    return null;
  },
);
