import 'package:boomerang/core/auth/user_session.dart';
import 'package:boomerang/core/utils/perf_log.dart';
import 'package:boomerang/core/navigation/home_tab_navigation.dart';
import 'package:boomerang/features/auth/presentation/signup_page.dart';
import 'package:boomerang/features/legal/presentation/legal_page.dart';
import 'package:boomerang/features/profile/application/profile_controller.dart';
import 'package:boomerang/features/profile/application/user_boomerangs_controller.dart';
import 'package:boomerang/features/feed/presentation/home_shell.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:boomerang/core/widgets/ui.dart';
import 'package:boomerang/core/utils/validators.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  static const String routeName = '/login';

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _rememberMe = false;
  bool _acceptedTerms = false;
  bool _acceptedPrivacy = false;
  bool _initializedFromRoute = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initializedFromRoute) return;
    _initializedFromRoute = true;

    final addAccountMode =
        GoRouterState.of(context).uri.queryParameters['addAccount'] == '1';

    if (addAccountMode) {
      _email.clear();
      _password.clear();
      _rememberMe = false;
      return;
    }

    if (kDebugMode) {
      _email.text = 'ayoubeb209@gmail.com';
      _password.text = 'ayoub123';
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController(text: _email.text.trim());
    final localFormKey = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reset password'),
          content: Form(
            key: localFormKey,
            child: TextFormField(
              controller: emailController,
              decoration: const InputDecoration(
                hintText: 'Email',
                prefixIcon: Icon(Icons.email_rounded),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: Validators.email,
              autofillHints: const [AutofillHints.email],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!localFormKey.currentState!.validate()) return;
                final email = emailController.text.trim();
                await ref
                    .read(authControllerProvider.notifier)
                    .resetPassword(email);
                if (!mounted) return;
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'If an account exists, a reset email has been sent.',
                    ),
                  ),
                );
              },
              child: const Text('Send'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      // Scaffold (adjustResize + resizeToAvoidBottomInset) already lifts for
      // the keyboard; do not also pad by viewInsets.bottom.
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(24.w, 12.h, 24.w, 12.h),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 16.h),
                Text(
                  'Login to your\nAccount',
                  style: TextStyle(
                    fontSize: 48.sp,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: 32.h),
                InputFilled(
                  controller: _email,
                  hint: 'Email or username',
                  icon: Icons.email_rounded,
                  keyboardType: TextInputType.emailAddress,
                  validator: Validators.emailOrUsername,
                ),
                SizedBox(height: 16.h),
                InputFilled(
                  controller: _password,
                  hint: 'Password',
                  icon: Icons.lock_rounded,
                  obscure: _obscure,
                  suffix: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                SizedBox(height: 16.h),
                Row(
                  children: [
                    Checkbox(
                      value: _rememberMe,
                      onChanged:
                          (v) => setState(() => _rememberMe = v ?? false),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                    ),
                    Text('Remember me', style: TextStyle(fontSize: 16.sp)),
                  ],
                ),
                SizedBox(height: 8.h),
                _ConsentCheckbox(
                  value: _acceptedTerms,
                  onChanged: (v) => setState(() => _acceptedTerms = v ?? false),
                  label: 'I agree to the ',
                  linkText: 'Terms of Service',
                  onLinkTap: () => showTermsOfService(context),
                ),
                SizedBox(height: 4.h),
                _ConsentCheckbox(
                  value: _acceptedPrivacy,
                  onChanged:
                      (v) => setState(() => _acceptedPrivacy = v ?? false),
                  label: 'I agree to the ',
                  linkText: 'Privacy Policy',
                  onLinkTap: () => showPrivacyPolicy(context),
                ),
                if (!_acceptedTerms || !_acceptedPrivacy)
                  Padding(
                    padding: EdgeInsets.only(top: 4.h, left: 12.w),
                    child: Text(
                      'You must accept both to sign in',
                      style: TextStyle(fontSize: 12.sp, color: Colors.black38),
                    ),
                  ),
                SizedBox(height: 16.h),
                PrimaryButton(
                  loading: state.loading || _submitting,
                  onPressed: () async {
                    if (_submitting) return;
                    if (!_formKey.currentState!.validate()) return;
                    final tapClock = Stopwatch()..start();
                    if (!_acceptedTerms || !_acceptedPrivacy) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Please accept the Terms of Service and Privacy Policy',
                          ),
                        ),
                      );
                      return;
                    }

                    setState(() => _submitting = true);
                    var keepLocked = false;
                    try {
                      // Snapshot the currently signed-in user (if any)
                      // BEFORE signIn replaces the Firebase session.
                      final prevUser =
                          ref.read(firebaseAuthProvider).currentUser;
                      final profileCandidate =
                          ref.read(currentUserProfileProvider).value;
                      final prevProfile =
                          prevUser != null &&
                                  profileCandidate != null &&
                                  profileCandidate.uid == prevUser.uid
                              ? profileCandidate
                              : null;
                      UserSession? prevSession;
                      if (prevUser != null) {
                        prevSession = UserSession(
                          uid: prevUser.uid,
                          email: prevProfile?.email ?? prevUser.email ?? '',
                          displayName:
                              prevProfile?.fullName.isNotEmpty == true
                                  ? prevProfile!.fullName
                                  : prevProfile?.nickname ??
                                      prevUser.displayName ??
                                      '',
                          photoUrl:
                              prevProfile?.avatarUrl ?? prevUser.photoURL,
                          lastLogin: DateTime.now(),
                        );
                      }

                      await ref
                          .read(authControllerProvider.notifier)
                          .login(
                            _email.text.trim(),
                            _password.text,
                            previousAccount: prevSession,
                          );
                      if (!mounted) return;
                      final authResult = ref.read(authControllerProvider);
                      final loginSucceeded =
                          authResult.error == null &&
                          authResult.success != null &&
                          ref.read(firebaseAuthProvider).currentUser != null;
                      if (loginSucceeded) {
                        // Stay locked through navigation so a second tap
                        // cannot fire while the route is still mounted.
                        keepLocked = true;
                        try {
                          await PerfLog.track(
                            'login.idTokenRefresh',
                            () async => ref
                                .read(firebaseAuthProvider)
                                .currentUser
                                ?.getIdToken(true),
                          );
                        } catch (_) {}
                        final container = ProviderScope.containerOf(
                          context,
                          listen: false,
                        );
                        invalidateUserScopedProviders(container);
                        container.invalidate(profileControllerProvider);
                        container.invalidate(userBoomerangsControllerProvider);
                        container.invalidate(storedAccountsProvider);
                        ref.read(homeTabIndexProvider.notifier).state = 0;
                        if (!mounted) return;
                        PerfLog.event(
                          'login NAVIGATE-TO-HOME',
                          'tapToHomeMs=${tapClock.elapsedMilliseconds}',
                        );
                        context.go(HomeShell.routeName);
                      }
                    } finally {
                      if (mounted && !keepLocked) {
                        setState(() => _submitting = false);
                      }
                    }
                  },
                  child: Text(
                    'Sign in',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(height: 12.h),
                Center(
                  child: TextButton(
                    onPressed: _showForgotPasswordDialog,
                    child: const Text('Forgot the password?'),
                  ),
                ),
                SizedBox(height: 24.h),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: TextStyle(fontSize: 14.sp, color: Colors.black54),
                    ),
                    GestureDetector(
                      onTap: () {
                        final addAccountMode =
                            GoRouterState.of(
                              context,
                            ).uri.queryParameters['addAccount'] ==
                            '1';
                        final signupTarget =
                            addAccountMode
                                ? '${SignupPage.routeName}?addAccount=1'
                                : SignupPage.routeName;
                        context.push(signupTarget);
                      },
                      child: Text(
                        'Sign up',
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                // Error and success messages
                if (state.error != null)
                  Padding(
                    padding: EdgeInsets.only(top: 12.h),
                    child: Text(
                      state.error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (state.success != null)
                  Padding(
                    padding: EdgeInsets.only(top: 12.h),
                    child: Text(
                      state.success!,
                      style: const TextStyle(color: Colors.green),
                    ),
                  ),
                SizedBox(height: 24.h),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Shared UI components are defined in core/widgets/ui.dart

class _ConsentCheckbox extends StatelessWidget {
  const _ConsentCheckbox({
    required this.value,
    required this.onChanged,
    required this.label,
    required this.linkText,
    required this.onLinkTap,
  });

  final bool value;
  final ValueChanged<bool?> onChanged;
  final String label;
  final String linkText;
  final VoidCallback onLinkTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 28.r,
          height: 28.r,
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4.r),
            ),
          ),
        ),
        SizedBox(width: 8.w),
        Flexible(
          child: GestureDetector(
            onTap: () => onChanged(!value),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: label,
                    style: TextStyle(fontSize: 13.sp, color: Colors.black54),
                  ),
                  WidgetSpan(
                    child: GestureDetector(
                      onTap: onLinkTap,
                      child: Text(
                        linkText,
                        style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
