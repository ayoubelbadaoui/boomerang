import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:boomerang/features/auth/presentation/onboarding_page.dart';

class ManageAccountPage extends ConsumerWidget {
  const ManageAccountPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).value;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: Text(
          'Manage Accounts',
          style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 32.h),
        children: [
          Text(
            'Account Information',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18.sp),
          ),
          _Item(
            icon: Icons.phone,
            label: 'Phone Number',
            value: '',
            onTap:
                () => _editText(
                  context,
                  ref,
                  'Phone Number',
                  initial: '',
                  onSubmit: (v) {
                    ref
                        .read(userProfileRepoProvider)
                        .updateCurrentUserProfile(phone: v.trim());
                  },
                ),
          ),
          _Item(
            icon: Icons.alternate_email,
            label: 'Email',
            value: profile?.uid ?? '', // show partial or custom email if stored
            onTap:
                () => _editText(
                  context,
                  ref,
                  'Email',
                  initial: profile?.uid ?? '',
                  onSubmit: (v) {
                    ref
                        .read(userProfileRepoProvider)
                        .updateCurrentUserProfile();
                  },
                ),
          ),
          _Item(
            icon: Icons.calendar_today,
            label: 'Date of Birth',
            value: '',
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                firstDate: DateTime(now.year - 100),
                lastDate: now,
                initialDate: DateTime(now.year - 18, now.month, now.day),
              );
              if (d != null) {
                await ref
                    .read(userProfileRepoProvider)
                    .updateCurrentUserProfile(birthday: d);
              }
            },
          ),
          SizedBox(height: 16.h),
          Text(
            'Account Control',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18.sp),
          ),
          _Item(
            icon: Icons.swap_vert,
            label: 'Switch to Business Account',
            onTap: () {},
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text(
              'Delete Account',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () async {
              await ref.read(userProfileRepoProvider).deleteAccount();
              // Ensure app session is cleared
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go(OnboardingPage.routeName);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _editText(
    BuildContext context,
    WidgetRef ref,
    String title, {
    String initial = '',
    required ValueChanged<String> onSubmit,
  }) async {
    final controller = TextEditingController(text: initial);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: title,
                      filled: true,
                      fillColor: const Color(0xFFF6F6F6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24.r),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16.w,
                        vertical: 14.h,
                      ),
                    ),
                    onSubmitted: (v) {
                      Navigator.pop(context);
                      onSubmit(v);
                    },
                  ),
                ),
                SizedBox(width: 12.w),
                InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    onSubmit(controller.text);
                  },
                  child: CircleAvatar(
                    radius: 24.r,
                    backgroundColor: Colors.black,
                    child: const Icon(Icons.check, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null && value!.isNotEmpty)
            Text(value!, style: const TextStyle(color: Colors.black54)),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
    );
  }
}
