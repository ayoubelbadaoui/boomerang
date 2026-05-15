import 'dart:async';
import 'dart:io';

import 'package:boomerang/core/widgets/avatar.dart';
import 'package:boomerang/features/auth/domain/username_validation.dart';
import 'package:boomerang/features/profile/application/profile_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:boomerang/core/utils/avatar_crop.dart';

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
                  if (_selected != null)
                    CircleAvatar(
                      radius: 68.r,
                      backgroundImage: FileImage(_selected!),
                      backgroundColor: Colors.grey.shade200,
                    )
                  else
                    AppAvatar(url: p?.avatarUrl, size: 136.r),
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
              onTap: () => _editUsername(currentNickname: p?.nickname ?? ''),
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
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    final file = await pickAndCropAvatar(ImageSource.gallery);
    if (file == null) return;
    setState(() => _selected = file);
    final url = await ref
        .read(profileControllerProvider.notifier)
        .uploadAvatar(_selected!);
    await ref
        .read(profileControllerProvider.notifier)
        .updateProfile(avatarUrl: url);
  }

  Future<void> _editUsername({required String currentNickname}) async {
    final newNickname = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _UsernameEditSheet(currentNickname: currentNickname),
    );
    if (newNickname == null || newNickname == currentNickname) return;
    try {
      await ref
          .read(profileControllerProvider.notifier)
          .updateProfile(nickname: newNickname);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username updated.')),
      );
    } catch (e) {
      if (!mounted) return;
      // Defensive: another user could grab the alias between the live
      // check and the submit, in which case the repo throws.
      final msg = e is StateError
          ? e.message
          : 'Could not update username. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
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
            bottom: MediaQuery.viewInsetsOf(context).bottom,
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

enum _UsernameStatus { idle, checking, available, taken, invalid, unchanged, error }

class _UsernameEditSheet extends ConsumerStatefulWidget {
  const _UsernameEditSheet({required this.currentNickname});
  final String currentNickname;

  @override
  ConsumerState<_UsernameEditSheet> createState() => _UsernameEditSheetState();
}

class _UsernameEditSheetState extends ConsumerState<_UsernameEditSheet> {
  late final TextEditingController _controller;
  Timer? _debounce;
  int _checkVersion = 0;
  _UsernameStatus _status = _UsernameStatus.unchanged;
  String? _hint = 'This is your current username.';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentNickname)
      ..addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    final raw = _controller.text.trim().toLowerCase();

    if (raw == widget.currentNickname.toLowerCase()) {
      setState(() {
        _status = _UsernameStatus.unchanged;
        _hint = 'This is your current username.';
      });
      return;
    }
    final validation = validateUsername(raw);
    if (!validation.isValid) {
      setState(() {
        _status = _UsernameStatus.invalid;
        _hint = validation.error;
      });
      return;
    }
    setState(() {
      _status = _UsernameStatus.checking;
      _hint = 'Checking availability\u2026';
    });
    final version = ++_checkVersion;
    _debounce = Timer(const Duration(milliseconds: 450), () {
      _check(raw, version);
    });
  }

  Future<void> _check(String candidate, int version) async {
    try {
      final available = await ref
          .read(profileControllerProvider.notifier)
          .isUsernameAvailable(candidate);
      if (!mounted || version != _checkVersion) return;
      setState(() {
        _status = available ? _UsernameStatus.available : _UsernameStatus.taken;
        _hint = available
            ? 'Username is available.'
            : 'Username is already taken.';
      });
    } catch (_) {
      if (!mounted || version != _checkVersion) return;
      setState(() {
        _status = _UsernameStatus.error;
        _hint = 'Could not verify username. Please try again.';
      });
    }
  }

  bool get _canSubmit =>
      _status == _UsernameStatus.available ||
      (_status == _UsernameStatus.unchanged &&
          _controller.text.trim().isNotEmpty);

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context).pop(_controller.text.trim().toLowerCase());
  }

  Color _hintColor() {
    switch (_status) {
      case _UsernameStatus.available:
        return Colors.green.shade700;
      case _UsernameStatus.taken:
      case _UsernameStatus.invalid:
      case _UsernameStatus.error:
        return Colors.red.shade700;
      case _UsernameStatus.unchanged:
      case _UsernameStatus.idle:
      case _UsernameStatus.checking:
        return Colors.black54;
    }
  }

  Widget _statusIcon() {
    switch (_status) {
      case _UsernameStatus.checking:
        return SizedBox(
          width: 18.r,
          height: 18.r,
          child: const CircularProgressIndicator(
            strokeWidth: 2.4,
            color: Colors.black54,
          ),
        );
      case _UsernameStatus.available:
        return Icon(Icons.check_circle, color: Colors.green.shade700, size: 22.r);
      case _UsernameStatus.taken:
      case _UsernameStatus.invalid:
      case _UsernameStatus.error:
        return Icon(Icons.cancel, color: Colors.red.shade700, size: 22.r);
      case _UsernameStatus.unchanged:
      case _UsernameStatus.idle:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Username',
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 12.h),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: 'username',
                      prefixText: '@',
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
                      suffixIcon: Padding(
                        padding: EdgeInsets.only(right: 12.w),
                        child: _statusIcon(),
                      ),
                      suffixIconConstraints:
                          BoxConstraints(minWidth: 24.r, minHeight: 24.r),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                InkWell(
                  onTap: _canSubmit ? _submit : null,
                  customBorder: const CircleBorder(),
                  child: Opacity(
                    opacity: _canSubmit ? 1 : 0.35,
                    child: CircleAvatar(
                      radius: 24.r,
                      backgroundColor: Colors.black,
                      child: const Icon(Icons.check, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8.h),
            if (_hint != null)
              Text(
                _hint!,
                style: TextStyle(color: _hintColor(), fontSize: 13.sp),
              ),
            SizedBox(height: 8.h),
            Text(
              'Lowercase letters, numbers, dot, or underscore. 3\u201320 characters.',
              style: TextStyle(color: Colors.black45, fontSize: 12.sp),
            ),
          ],
        ),
      ),
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
