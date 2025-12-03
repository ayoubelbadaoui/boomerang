import 'dart:io';

import 'package:boomerang/features/profile/application/profile_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';

class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});
  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  File? _selected;

  @override
  Widget build(BuildContext context) {
    final asyncProfile = ref.watch(profileControllerProvider);
    final p = asyncProfile.value;
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        toolbarHeight: 0,
      ),
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 32.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                ),
                SizedBox(width: 8.w),
                Text(
                  'Edit Profile',
                  style: TextStyle(
                    fontSize: 28.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16.h),
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 68.r,
                    backgroundImage:
                        _selected != null
                            ? FileImage(_selected!)
                            : (p?.avatarUrl != null
                                    ? NetworkImage(p!.avatarUrl!)
                                    : null)
                                as ImageProvider<Object>?,
                    onBackgroundImageError:
                        (_selected != null || p?.avatarUrl != null)
                            ? (_, __) {}
                            : null,
                    backgroundColor: const Color(0xFFF2F2F2),
                    child:
                        (_selected == null && p?.avatarUrl == null)
                            ? const Icon(
                              Icons.person,
                              color: Colors.black26,
                              size: 48,
                            )
                            : null,
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: InkWell(
                      onTap: _pickImage,
                      child: Container(
                        height: 36,
                        width: 36,
                        decoration: const BoxDecoration(
                          color: Colors.black,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16.h),
            const Divider(),
            SizedBox(height: 12.h),
            Text(
              'About You',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18.sp),
            ),
            SizedBox(height: 8.h),
            _NavItem(
              icon: Icons.person_outline,
              label: 'Name',
              value: p?.fullName ?? '',
              onTap:
                  () => _editValue(
                    title: 'Name',
                    initial: p?.fullName ?? '',
                    onSubmit:
                        (v) => ref
                            .read(profileControllerProvider.notifier)
                            .updateProfile(
                              fullName: v.trim().isEmpty ? null : v.trim(),
                            ),
                  ),
            ),
            const Divider(height: 1),
            _NavItem(
              icon: Icons.verified_outlined,
              label: 'Username',
              value: p?.nickname ?? '',
              onTap:
                  () => _editValue(
                    title: 'Username',
                    initial: p?.nickname ?? '',
                    onSubmit:
                        (v) => ref
                            .read(profileControllerProvider.notifier)
                            .updateProfile(
                              nickname: v.trim().isEmpty ? null : v.trim(),
                            ),
                  ),
            ),
            const Divider(height: 1),
            _NavItem(
              icon: Icons.info_outline,
              label: 'Bio',
              value: p?.bio ?? '',
              onTap:
                  () => _editValue(
                    title: 'Bio',
                    initial: p?.bio ?? '',
                    maxLines: 4,
                    onSubmit:
                        (v) => ref
                            .read(profileControllerProvider.notifier)
                            .updateProfile(bio: v.trim()),
                  ),
            ),
            SizedBox(height: 12.h),
            const Divider(),
            SizedBox(height: 12.h),
            Text(
              'Social',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18.sp),
            ),
            _NavItem(
              icon: Icons.camera_alt_outlined,
              label: 'Instagram',
              value: p?.instagram ?? '',
              onTap:
                  () => _editValue(
                    title: 'Instagram',
                    initial: p?.instagram ?? '',
                    onSubmit:
                        (v) => ref
                            .read(profileControllerProvider.notifier)
                            .updateProfile(instagram: v.trim()),
                  ),
            ),
            const Divider(height: 1),
            _NavItem(
              icon: Icons.facebook_outlined,
              label: 'Facebook',
              value: p?.facebook ?? '',
              onTap:
                  () => _editValue(
                    title: 'Facebook',
                    initial: p?.facebook ?? '',
                    onSubmit:
                        (v) => ref
                            .read(profileControllerProvider.notifier)
                            .updateProfile(facebook: v.trim()),
                  ),
            ),
            const Divider(height: 1),
            _NavItem(
              icon: Icons.alternate_email,
              label: 'Twitter',
              value: p?.twitter ?? '',
              onTap:
                  () => _editValue(
                    title: 'Twitter',
                    initial: p?.twitter ?? '',
                    onSubmit:
                        (v) => ref
                            .read(profileControllerProvider.notifier)
                            .updateProfile(twitter: v.trim()),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final res = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (res == null) return;
    setState(() => _selected = File(res.path));
    final url = await ref
        .read(profileControllerProvider.notifier)
        .uploadAvatar(_selected!);
    await ref
        .read(profileControllerProvider.notifier)
        .updateProfile(avatarUrl: url);
  }

  Future<void> _editValue({
    required String title,
    required String initial,
    required ValueChanged<String> onSubmit,
    int maxLines = 1,
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
                    maxLines: maxLines,
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value.isEmpty
                ? ''
                : (value.length > 18 ? '${value.substring(0, 18)}…' : value),
            style: const TextStyle(color: Colors.black87),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
    );
  }
}
