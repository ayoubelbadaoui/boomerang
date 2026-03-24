import 'package:boomerang/core/notifications/push_notifications_service.dart';
import 'package:boomerang/features/profile/application/profile_controller.dart';
import 'package:boomerang/features/profile/application/user_boomerangs_controller.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:boomerang/features/auth/presentation/onboarding_page.dart';

class ManageAccountPage extends ConsumerWidget {
  const ManageAccountPage({super.key});
  String _formatDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';

  String _truncate(String s, int max) =>
      s.length > max ? '${s.substring(0, max)}...' : s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).value;
    final authEmail =
        ref.watch(firebaseAuthProvider).currentUser?.email ?? '';
    final displayEmail =
        profile != null && profile.email.isNotEmpty ? profile.email : authEmail;
    final displayPhone = profile?.phone ?? '';
    final displayBirthday = profile?.birthday;

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
            icon: Icons.phone_outlined,
            label: 'Phone Number',
            value: displayPhone.isNotEmpty
                ? _truncate(displayPhone, 14)
                : null,
            onTap: () => _editText(
              context,
              ref,
              'Phone Number',
              initial: displayPhone,
              onSubmit: (v) async {
                await ref
                    .read(userProfileRepoProvider)
                    .updateCurrentUserProfile(phone: v.trim());
              },
            ),
          ),
          _Item(
            icon: Icons.mail_outline_rounded,
            label: 'Email',
            value: displayEmail.isNotEmpty
                ? _truncate(displayEmail, 14)
                : null,
            onTap: () => _editText(
              context,
              ref,
              'Email',
              initial: displayEmail,
              onSubmit: (v) async {
                await ref
                    .read(userProfileRepoProvider)
                    .updateCurrentUserProfile(email: v.trim());
              },
            ),
          ),
          _Item(
            icon: Icons.calendar_today_outlined,
            label: 'Date of Birth',
            value: displayBirthday != null
                ? _formatDate(displayBirthday)
                : null,
            trailing: const Icon(Icons.calendar_today, size: 20),
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                firstDate: DateTime(now.year - 100),
                lastDate: now,
                initialDate: displayBirthday ??
                    DateTime(now.year - 18, now.month, now.day),
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
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete Account'),
                  content: const Text(
                    'Are you sure you want to delete your account? '
                    'This action is permanent and cannot be undone.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirmed != true) return;
              if (!context.mounted) return;
              final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
              if (uid != null && uid.isNotEmpty) {
                await removeCurrentDeviceTokenForUser(
                  ref.read(firestoreProvider),
                  uid,
                );
                await ref.read(multiAccountManagerProvider).removeAccount(uid);
              }
              await ref.read(userProfileRepoProvider).deleteAccount();
              await ref.read(authControllerProvider.notifier).logout();
              final container = ProviderScope.containerOf(context, listen: false);
              invalidateUserScopedProviders(container);
              container.invalidate(profileControllerProvider);
              container.invalidate(userBoomerangsControllerProvider);
              container.invalidate(storedAccountsProvider);
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
    required Future<void> Function(String) onSubmit,
  }) async {
    final controller = TextEditingController(text: initial);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
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
                      Navigator.pop(sheetCtx);
                      onSubmit(v);
                    },
                  ),
                ),
                SizedBox(width: 12.w),
                InkWell(
                  onTap: () {
                    Navigator.pop(sheetCtx);
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
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String? value;
  final Widget? trailing;
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
          SizedBox(width: 4.w),
          trailing ?? const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
    );
  }
}
