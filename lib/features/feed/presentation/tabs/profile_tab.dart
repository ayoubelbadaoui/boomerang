import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/auth/presentation/onboarding_page.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  static const String routeName = '/profile_tab';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () {},
          icon: const Icon(
            Icons.person_add_alt_1_outlined,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            profile.when(
              data:
                  (p) => Text(
                    (p?.fullName.isNotEmpty == true
                        ? p!.fullName
                        : p?.nickname ?? ''),
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const Text('Profile'),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _showSettingsSheet(context, ref),
            icon: const Icon(Icons.settings_outlined, color: Colors.black),
          ),
        ],
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Failed to load profile')),
        data:
            (p) => SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(height: 8.h),
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 48.r,
                        backgroundImage:
                            p?.avatarUrl != null
                                ? NetworkImage(p!.avatarUrl!)
                                : null,
                        backgroundColor: const Color(0xFFF2F2F2),
                        child:
                            p?.avatarUrl == null
                                ? const Icon(
                                  Icons.person,
                                  color: Colors.black26,
                                  size: 36,
                                )
                                : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          height: 24.r,
                          width: 24.r,
                          decoration: const BoxDecoration(
                            color: Colors.black,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12.h),
                  if (p != null && p.nickname.isNotEmpty)
                    Text(
                      '@${p.nickname.replaceAll(' ', '_').toLowerCase()}',
                      style: TextStyle(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  SizedBox(height: 6.h),
                  if (p != null && p.bio.isNotEmpty)
                    Text(
                      p.bio,
                      style: TextStyle(color: Colors.black54, fontSize: 14.sp),
                      textAlign: TextAlign.center,
                    ),
                  SizedBox(height: 20.h),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      _Stat(value: '247', label: 'Bmg.'),
                      _Stat(value: '368K', label: 'Followers'),
                      _Stat(value: '374', label: 'Following'),
                      _Stat(value: '3.7M', label: 'Likes'),
                    ],
                  ),
                  SizedBox(height: 16.h),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed:
                          () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const _EditProfilePage(),
                            ),
                          ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.black, width: 1),
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: StadiumBorder(
                          side: BorderSide(color: Colors.black, width: 1.w),
                        ),
                      ),
                      icon: const Icon(
                        Icons.circle,
                        size: 10,
                        color: Colors.black,
                      ),
                      label: Text(
                        'Edit Profile',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: const [
                      _ModeIcon(icon: Icons.grid_on_rounded, active: true),
                      _ModeIcon(icon: Icons.bookmark_border_rounded),
                      _ModeIcon(icon: Icons.favorite_border_rounded),
                    ],
                  ),
                  SizedBox(height: 12.h),
                  Divider(height: 1.h, color: Colors.black12),
                  SizedBox(height: 12.h),
                  _PostsGrid(),
                  SizedBox(height: 80.h),
                ],
              ),
            ),
      ),
    );
  }
}

void _showSettingsSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(height: 16.h),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text(
                'Log out',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await ref.read(authControllerProvider.notifier).logout();
                if (context.mounted) {
                  context.go(OnboardingPage.routeName);
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    },
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 4.h),
        Text(label, style: TextStyle(fontSize: 12.sp, color: Colors.black54)),
      ],
    );
  }
}

class _ModeIcon extends StatelessWidget {
  const _ModeIcon({required this.icon, this.active = false});
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36.r,
      width: 36.r,
      decoration: BoxDecoration(
        color: active ? Colors.black : Colors.transparent,
        borderRadius: BorderRadius.circular(10.r),
        border: active ? null : Border.all(color: Colors.black12),
      ),
      child: Icon(
        icon,
        color: active ? Colors.white : Colors.black54,
        size: 18.r,
      ),
    );
  }
}

class _PostsGrid extends StatelessWidget {
  final List<String> _imgs = const [
    'https://picsum.photos/seed/p1/800/800',
    'https://picsum.photos/seed/p2/800/800',
    'https://picsum.photos/seed/p3/800/800',
    'https://picsum.photos/seed/p4/800/800',
    'https://picsum.photos/seed/p5/800/800',
    'https://picsum.photos/seed/p6/800/800',
    'https://picsum.photos/seed/p7/800/800',
    'https://picsum.photos/seed/p8/800/800',
    'https://picsum.photos/seed/p9/800/800',
  ];

  const _PostsGrid();

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: _imgs.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8.w,
        crossAxisSpacing: 8.w,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12.r),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                _imgs[index],
                fit: BoxFit.cover,
                errorBuilder:
                    (context, _, __) => Container(color: Colors.black12),
              ),
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.remove_red_eye,
                        size: 12,
                        color: Colors.white70,
                      ),
                      SizedBox(width: 4.w),
                      const Text(
                        '367.5K',
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EditProfilePage extends ConsumerStatefulWidget {
  const _EditProfilePage();
  @override
  ConsumerState<_EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<_EditProfilePage> {
  File? _selected;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _nickCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _igCtrl;
  late final TextEditingController _fbCtrl;
  late final TextEditingController _twCtrl;
  bool _prefilled = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Initialize empty; we'll prefill from provider when available
    _nameCtrl = TextEditingController();
    _nickCtrl = TextEditingController();
    _bioCtrl = TextEditingController();
    _igCtrl = TextEditingController();
    _fbCtrl = TextEditingController();
    _twCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nickCtrl.dispose();
    _bioCtrl.dispose();
    _igCtrl.dispose();
    _fbCtrl.dispose();
    _twCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(currentUserProfileProvider).value;
    // Prefill once when profile is available
    ref.listen(currentUserProfileProvider, (prev, next) {
      final profile = next.value;
      if (!_prefilled && profile != null) {
        _nameCtrl.text = profile.fullName;
        _nickCtrl.text = profile.nickname;
        _bioCtrl.text = profile.bio;
        _igCtrl.text = profile.instagram;
        _fbCtrl.text = profile.facebook;
        _twCtrl.text = profile.twitter;
        _prefilled = true;
      }
    });
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
                                as ImageProvider?,
                    backgroundColor: const Color(0xFFF2F2F2),
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
            _ListItem(label: 'Name', controller: _nameCtrl),
            const Divider(height: 1),
            _ListItem(label: 'Username', controller: _nickCtrl),
            const Divider(height: 1),
            _ListItem(label: 'Bio', controller: _bioCtrl),
            SizedBox(height: 12.h),
            const Divider(),
            SizedBox(height: 12.h),
            Text(
              'Social',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18.sp),
            ),
            _ListItem(label: 'Instagram', controller: _igCtrl),
            const Divider(height: 1),
            _ListItem(label: 'Facebook', controller: _fbCtrl),
            const Divider(height: 1),
            _ListItem(label: 'Twitter', controller: _twCtrl),
            SizedBox(height: 24.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                ),
                child:
                    _saving
                        ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Text('Save changes'),
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
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    String? avatarUrl;
    if (_selected != null) {
      avatarUrl = await ref
          .read(userProfileRepoProvider)
          .uploadAvatar(_selected!);
    }
    await ref
        .read(userProfileRepoProvider)
        .updateCurrentUserProfile(
          fullName:
              _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
          nickname:
              _nickCtrl.text.trim().isEmpty ? null : _nickCtrl.text.trim(),
          bio: _bioCtrl.text.trim(),
          instagram: _igCtrl.text.trim(),
          facebook: _fbCtrl.text.trim(),
          twitter: _twCtrl.text.trim(),
          avatarUrl: avatarUrl,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
  }
}

class _ListItem extends StatelessWidget {
  const _ListItem({required this.label, required this.controller});
  final String label;
  final TextEditingController controller;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 16.sp))),
          Expanded(
            flex: 2,
            child: TextField(
              textAlign: TextAlign.right,
              controller: controller,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '',
              ),
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
