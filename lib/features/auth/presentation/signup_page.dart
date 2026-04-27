import 'package:boomerang/core/auth/user_session.dart';
import 'package:boomerang/features/auth/presentation/setup_flow_page.dart';
import 'package:boomerang/features/legal/presentation/legal_page.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/core/widgets/ui.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

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
  final _confirmPassword = TextEditingController();
  bool _acceptedTerms = false;
  bool _acceptedPrivacy = false;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _password.dispose();
    _confirmPassword.dispose();
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
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            24.w,
            12.h,
            24.w,
            12.h + MediaQuery.viewInsetsOf(context).bottom,
          ),
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
                SizedBox(height: 16.h),
                InputFilled(
                  controller: _confirmPassword,
                  hint: 'Confirm Password',
                  icon: Icons.lock_rounded,
                  obscure: true,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v != _password.text) return 'Passwords do not match';
                    return null;
                  },
                ),
                SizedBox(height: 16.h),
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
                  onChanged: (v) =>
                      setState(() => _acceptedPrivacy = v ?? false),
                  label: 'I agree to the ',
                  linkText: 'Privacy Policy',
                  onLinkTap: () => showPrivacyPolicy(context),
                ),
                if (!_acceptedTerms || !_acceptedPrivacy)
                  Padding(
                    padding: EdgeInsets.only(top: 4.h, left: 12.w),
                    child: Text(
                      'You must accept both to create an account',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Colors.black38,
                      ),
                    ),
                  ),
                SizedBox(height: 16.h),
                PrimaryButton(
                  loading: state.loading,
                  onPressed: () async {
                    if (!_formKey.currentState!.validate()) return;
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

                    final prevUser = ref.read(firebaseAuthProvider).currentUser;
                    final prevProfile =
                        ref.read(currentUserProfileProvider).value;
                    UserSession? prevSession;
                    if (prevUser != null) {
                      prevSession = UserSession(
                        uid: prevUser.uid,
                        email: prevProfile?.email ??
                            prevUser.email ??
                            '',
                        displayName: prevProfile?.fullName.isNotEmpty == true
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
                        .signup(
                          _email.text,
                          _password.text,
                          _name.text,
                          previousAccount: prevSession,
                        );
                    if (!mounted) return;
                    final result = ref.read(authControllerProvider);
                    if (result.error == null) {
                      _storeConsent(ref);
                      context.go(SetupFlowPage.routeName);
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

  void _storeConsent(WidgetRef ref) {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) return;
    ref.read(firestoreProvider).collection('users').doc(uid).set({
      'consentTermsAt': DateTime.now().toIso8601String(),
      'consentPrivacyAt': DateTime.now().toIso8601String(),
      'consentTermsVersion': '1.0',
      'consentPrivacyVersion': '1.0',
    }, SetOptions(merge: true));
  }
}

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
