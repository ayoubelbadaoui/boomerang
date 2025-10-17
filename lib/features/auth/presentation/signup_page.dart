import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/core/widgets/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
// intl not needed after removing birthday from signup

class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  static const String routeName = '/signup';

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  // Removed birthday; will be collected in setup

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
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
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 16.h),
                Text(
                  'Create your\nAccount',
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
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                SizedBox(height: 16.h),
                InputFilled(
                  controller: _name,
                  hint: 'Name',
                  icon: Icons.person_rounded,
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                SizedBox(height: 16.h),
                InputFilled(
                  controller: _password,
                  hint: 'Password',
                  icon: Icons.lock_rounded,
                  obscure: true,
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                // Birthday removed from signup; handled in post-signup setup
                SizedBox(height: 24.h),
                PrimaryButton(
                  loading: state.loading,
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      await ref
                          .read(authControllerProvider.notifier)
                          .signup(_email.text, _password.text, _name.text);
                      if (mounted) context.push('/setup/profile');
                    }
                  },
                  child: Text(
                    'Sign up',
                    style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w700,
                    ),
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
                      'Already have an account? ',
                      style: TextStyle(fontSize: 14.sp, color: Colors.black54),
                    ),
                    GestureDetector(
                      onTap: () => context.go('/login'),
                      child: Text(
                        'Sign in',
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (state.error != null)
                  Padding(
                    padding: EdgeInsets.only(top: 12.h),
                    child: Text(
                      state.error!,
                      style: const TextStyle(color: Colors.red),
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
