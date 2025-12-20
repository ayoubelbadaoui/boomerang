import 'package:boomerang/features/auth/presentation/signup_page.dart';
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

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      _email.text = 'ayoubeb209@gmail.com';
      _password.text = 'ayoub123';
    }
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
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            24.w,
            12.h,
            24.w,
            12.h + MediaQuery.of(context).viewInsets.bottom,
          ),
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
                  hint: 'Email',
                  icon: Icons.email_rounded,
                  keyboardType: TextInputType.emailAddress,
                  validator: Validators.email,
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
                PrimaryButton(
                  loading: state.loading,
                  onPressed: () async {
                    if (!_formKey.currentState!.validate()) return;
                    await ref
                        .read(authControllerProvider.notifier)
                        .login(_email.text, _password.text);
                    if (!mounted) return;
                    final next = ref.read(authStateProvider).asData?.value;
                    if (next != null) {
                      // Navigate to home and clear back stack
                      context.go(HomeShell.routeName);
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
                const SectionDivider(label: 'or continue with'),
                SizedBox(height: 20.h),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: const [
                    SocialButton(icon: Icons.facebook),
                    SocialButton(icon: Icons.g_mobiledata),
                    SocialButton(icon: Icons.apple),
                  ],
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
                      onTap: () => context.push(SignupPage.routeName),
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
