import 'package:boomerang/features/splash_screen/presentation/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/auth/presentation/signup_page.dart';
import 'features/feed/presentation/home_shell.dart';
import 'features/auth/presentation/onboarding_page.dart';
import 'features/auth/presentation/auth_choice_page.dart';
import 'features/auth/presentation/setup_profile_page.dart';
import 'features/auth/presentation/setup_flow_page.dart';
import 'features/profile/presentation/settings/settings_page.dart';
import 'features/chat/presentation/pages/conversations_page.dart';
import 'features/chat/presentation/pages/chat_page.dart';
import 'features/feed/presentation/single_boomerang_page.dart';
import 'infrastructure/providers.dart';

/// Bridges Riverpod auth/profile state to GoRouter so the redirect
/// re-evaluates whenever any of its inputs change. Without this, the
/// router only runs `redirect` once at boot — if auth is still loading
/// at that moment, the splash never advances.
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(this._ref) {
    _subs = [
      _ref.listen<Object?>(authStateProvider, (_, __) => notifyListeners()),
      _ref.listen<Object?>(
        userHasNicknameProvider,
        (_, __) => notifyListeners(),
      ),
      _ref.listen<Object?>(
        userProfileExistsProvider,
        (_, __) => notifyListeners(),
      ),
      _ref.listen<Object?>(
        userProfileCompleteProvider,
        (_, __) => notifyListeners(),
      ),
      _ref.listen<Object?>(
        isSwitchingAccountProvider,
        (_, __) => notifyListeners(),
      ),
    ];
  }

  final Ref _ref;
  late final List<ProviderSubscription<Object?>> _subs;

  @override
  void dispose() {
    for (final s in _subs) {
      s.close();
    }
    super.dispose();
  }
}

/// The single GoRouter instance lives behind a provider so it can carry a
/// `refreshListenable` driven by Riverpod. Consumed once in `app.dart` via
/// `ref.watch(routerProvider)`.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefreshNotifier(ref);
  ref.onDispose(refresh.dispose);
  return _buildRouter(refresh);
});

NoTransitionPage<void> _startupPage({
  required GoRouterState state,
  required Widget child,
}) => NoTransitionPage<void>(key: state.pageKey, child: child);

GoRouter _buildRouter(Listenable refresh) => GoRouter(
  refreshListenable: refresh,
  initialLocation: SplashScreen.routeName,

  routes: [
    GoRoute(
      path: SplashScreen.routeName,
      pageBuilder:
          (c, s) => _startupPage(state: s, child: const SplashScreen()),
    ),
    GoRoute(
      path: OnboardingPage.routeName,
      pageBuilder:
          (c, s) => _startupPage(state: s, child: const OnboardingPage()),
    ),
    GoRoute(
      path: AuthChoicePage.routeName,
      pageBuilder:
          (c, s) => _startupPage(state: s, child: const AuthChoicePage()),
    ),
    GoRoute(
      path: LoginPage.routeName,
      pageBuilder: (c, s) => _startupPage(state: s, child: const LoginPage()),
    ),
    GoRoute(
      path: SignupPage.routeName,
      pageBuilder: (c, s) => _startupPage(state: s, child: const SignupPage()),
    ),
    GoRoute(
      path: SetupProfilePage.routeName,
      builder: (c, s) => const SetupProfilePage(),
    ),
    GoRoute(
      path: SetupFlowPage.routeName,
      pageBuilder:
          (c, s) => _startupPage(state: s, child: const SetupFlowPage()),
    ),
    GoRoute(
      path: HomeShell.routeName,
      pageBuilder: (c, s) => _startupPage(state: s, child: const HomeShell()),
    ),
    GoRoute(
      path: SettingsPage.routeName,
      builder: (c, s) => const SettingsPage(),
    ),
    GoRoute(
      path: ConversationsPage.routeName,
      builder: (c, s) => const ConversationsPage(),
    ),
    GoRoute(
      path: '/chat/:conversationId',
      builder:
          (c, s) =>
              ChatPage(conversationId: s.pathParameters['conversationId']!),
    ),
    GoRoute(
      path: '/boomerang/:boomerangId',
      builder:
          (c, s) => SingleBoomerangPage(
            boomerangId: s.pathParameters['boomerangId']!,
          ),
    ),
  ],
  redirect: (context, state) {
    final container = ProviderScope.containerOf(context, listen: false);
    final auth = container.read(authStateProvider);
    final profileExists = container.read(userProfileExistsProvider);
    final profileComplete = container.read(userProfileCompleteProvider);
    final hasNickname = container.read(userHasNicknameProvider);
    final isSplash = state.fullPath == SplashScreen.routeName;
    final isAuthChoice = state.fullPath == AuthChoicePage.routeName;
    final isLogin = state.fullPath == LoginPage.routeName;
    final isSignup = state.fullPath == SignupPage.routeName;
    final isOnboarding = state.fullPath == OnboardingPage.routeName;
    final isSetupFlow = state.fullPath == SetupFlowPage.routeName;

    // While an account switch is in progress, don't react to transient
    // sign-out states — let the switch complete before applying guards.
    final isSwitching = container.read(isSwitchingAccountProvider);
    if (isSwitching) return null;

    if (auth.asData == null) return null; // wait until first frame resolves
    final user = auth.asData!.value;

    if (user == null) {
      // Splash is a hand-off-only screen; once we know there is no
      // authenticated user, push to onboarding. Other auth-entry pages
      // (login/signup/onboarding/auth-choice) are valid terminals.
      final isAuthEntry = isOnboarding || isAuthChoice || isLogin || isSignup;
      return isAuthEntry ? null : OnboardingPage.routeName;
    }

    // User signed in: wait for nickname/profile checks.
    // Treat loading OR error as "still resolving" — never redirect based on
    // a transient Firestore error (it would bounce users to setup in a loop).
    if (hasNickname.asData == null ||
        profileExists.asData == null ||
        profileComplete.asData == null ||
        hasNickname.hasError ||
        profileExists.hasError ||
        profileComplete.hasError) {
      return null;
    }
    final hasName = hasNickname.asData!.value;
    final hasProfile = profileExists.asData!.value;
    final isComplete = profileComplete.asData!.value;

    final shouldRunSetup = !hasName || !hasProfile || !isComplete;
    if (shouldRunSetup) {
      return isSetupFlow ? null : SetupFlowPage.routeName;
    }

    if (isSplash ||
        isOnboarding ||
        isAuthChoice ||
        isLogin ||
        isSignup ||
        isSetupFlow) {
      return HomeShell.routeName;
    }
    return null;
  },
);
