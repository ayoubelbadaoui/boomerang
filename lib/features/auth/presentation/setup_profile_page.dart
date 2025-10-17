import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:boomerang/core/widgets/ui.dart';

class SetupProfilePage extends StatefulWidget {
  const SetupProfilePage({super.key});

  static const String routeName = '/setup/profile';

  @override
  State<SetupProfilePage> createState() => _SetupProfilePageState();
}

class _SetupProfilePageState extends State<SetupProfilePage> {
  final _fullName = TextEditingController();
  final _nickname = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();

  @override
  void dispose() {
    _fullName.dispose();
    _nickname.dispose();
    _email.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Fill Your Profile'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.h),
          child: Column(
            children: [
              SizedBox(height: 16.h),
              CircleAvatar(
                radius: 64.r,
                backgroundColor: const Color(0xFFF2F2F2),
              ),
              SizedBox(height: 24.h),
              InputFilled(
                controller: _fullName,
                hint: 'Full Name',
                icon: Icons.person,
              ),
              SizedBox(height: 12.h),
              InputFilled(
                controller: _nickname,
                hint: 'Nickname',
                icon: Icons.alternate_email,
              ),
              SizedBox(height: 12.h),
              InputFilled(
                controller: _email,
                hint: 'Email',
                icon: Icons.email,
                keyboardType: TextInputType.emailAddress,
              ),
              SizedBox(height: 12.h),
              InputFilled(
                controller: _phone,
                hint: 'Phone Number',
                icon: Icons.phone,
                keyboardType: TextInputType.phone,
              ),
              SizedBox(height: 12.h),
              InputFilled(
                controller: _address,
                hint: 'Address',
                icon: Icons.location_on,
              ),
              SizedBox(height: 24.h),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 16.h),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () => context.go('/home'),
                      child: const Text('Skip'),
                    ),
                  ),
                  SizedBox(width: 16.w),
                  Expanded(
                    child: PrimaryButton(
                      onPressed: () => context.go('/home'),
                      child: Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
