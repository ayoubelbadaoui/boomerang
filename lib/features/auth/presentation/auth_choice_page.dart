import 'package:boomerang/features/auth/presentation/widgets/social_auth_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'login_page.dart';
import 'signup_page.dart';

class AuthChoicePage extends StatelessWidget {
  const AuthChoicePage({super.key});

  static const String routeName = '/auth';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: 24.h),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24.r),
                  child: Image.asset(
                    'assets/logo.png',
                    width: 120.w,
                    height: 120.w,
                  ),
                ),
              ),
              SizedBox(height: 40.h),
              Text(
                "Let's you in",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 48.sp,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              SizedBox(height: 40.h),
              AuthButton(
                icon: Icons.facebook,
                label: 'Continue with Facebook',
                onPressed: () {},
              ),
              SizedBox(height: 16.h),
              AuthButton(
                icon: Icons.g_mobiledata,
                label: 'Continue with Google',
                onPressed: () {},
              ),
              SizedBox(height: 16.h),
              AuthButton(
                icon: Icons.apple,
                label: 'Continue with Apple',
                onPressed: () {},
              ),
              SizedBox(height: 32.h),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12.w),
                    child: Text('or', style: TextStyle(fontSize: 14.sp)),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              SizedBox(height: 24.h),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    padding: EdgeInsets.symmetric(vertical: 16.h),
                  ),
                  onPressed: () => context.push(LoginPage.routeName),
                  child: Text(
                    'Sign in with password',
                    style: TextStyle(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
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
              SizedBox(height: 24.h),
            ],
          ),
        ),
      ),
    );
  }
}
