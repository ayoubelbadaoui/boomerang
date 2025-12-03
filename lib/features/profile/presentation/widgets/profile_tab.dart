import 'package:boomerang/features/profile/application/profile_controller.dart';
import 'package:boomerang/features/profile/presentation/widgets/edit_profile_page.dart';
import 'package:boomerang/features/profile/presentation/widgets/mode_icon.dart';
import 'package:boomerang/features/profile/presentation/widgets/user_boomerangs_grid.dart';
import 'package:boomerang/features/profile/presentation/widgets/stat.dart';
import 'package:boomerang/features/profile/presentation/sheets/follow_list_sheet.dart';
import 'package:boomerang/features/profile/presentation/settings/settings_page.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'dart:developer' show log;

class ProfileTab extends ConsumerWidget {
  const ProfileTab({super.key});

  static const String routeName = '/profile_tab';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileControllerProvider);

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
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
            },
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
                  InkWell(
                    onTap: () => _showAvatarPickerSheet(context, ref),
                    borderRadius: BorderRadius.circular(48.r),
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 48.r,
                          backgroundImage:
                              p?.avatarUrl != null
                                  ? ResizeImage.resizeIfNeeded(
                                    (96.r *
                                            MediaQuery.of(
                                              context,
                                            ).devicePixelRatio)
                                        .round(),
                                    (96.r *
                                            MediaQuery.of(
                                              context,
                                            ).devicePixelRatio)
                                        .round(),
                                    NetworkImage(p!.avatarUrl!),
                                  )
                                  : null,
                          onBackgroundImageError:
                              p?.avatarUrl != null
                                  ? (ex, st) {
                                    log(
                                      'Avatar image load error',
                                      name: 'ProfileTab',
                                      error: ex,
                                      stackTrace: st,
                                    );
                                  }
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
                    children: [
                      const Stat(value: '247', label: 'Bmg.'),
                      Builder(
                        builder: (_) {
                          final uid = p?.uid ?? '';
                          final followers = ref.watch(followersCountProvider(uid));
                          final followersText = followers.maybeWhen(
                            data: (v) => '$v',
                            orElse: () => '0',
                          );
                          return Stat(
                            value: followersText,
                            label: 'Followers',
                            onTap: () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.white,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(24),
                                ),
                              ),
                              builder: (_) => const SizedBox(
                                height: 500,
                                child: FollowListSheet(
                                  mode: FollowMode.followers,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      Builder(
                        builder: (_) {
                          final uid = p?.uid ?? '';
                          final following = ref.watch(followingCountProvider(uid));
                          final followingText = following.maybeWhen(
                            data: (v) => '$v',
                            orElse: () => '0',
                          );
                          return Stat(
                            value: followingText,
                            label: 'Following',
                            onTap: () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.white,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(24),
                                ),
                              ),
                              builder: (_) => const SizedBox(
                                height: 500,
                                child: FollowListSheet(
                                  mode: FollowMode.following,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const Stat(value: '3.7M', label: 'Likes'),
                    ],
                  ),
                  SizedBox(height: 16.h),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed:
                          () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const EditProfilePage(),
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
                      ModeIcon(icon: Icons.grid_on_rounded, active: true),
                      ModeIcon(icon: Icons.bookmark_border_rounded),
                      ModeIcon(icon: Icons.favorite_border_rounded),
                    ],
                  ),
                  SizedBox(height: 12.h),
                  Divider(height: 1.h, color: Colors.black12),
                  SizedBox(height: 12.h),
                  const UserBoomerangsGrid(),
                  SizedBox(height: 80.h),
                ],
              ),
            ),
      ),
    );
  }
}

// settings bottom sheet replaced by full settings page

Future<void> _pickAvatarAndUpdate(
  BuildContext context,
  WidgetRef ref, {
  required ImageSource source,
}) async {
  try {
    final picker = ImagePicker();
    final res = await picker.pickImage(source: source, imageQuality: 90);
    if (res == null) return;
    final file = File(res.path);
    final url = await ref
        .read(profileControllerProvider.notifier)
        .uploadAvatar(file);
    await ref
        .read(profileControllerProvider.notifier)
        .updateProfile(avatarUrl: url);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile photo updated')));
    }
  } catch (e) {
    if (context.mounted) {
      log('Failed to update profile photo', name: 'ProfileTab', error: e);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update photo: $e')));
    }
  }
}

void _showAvatarPickerSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _pickAvatarAndUpdate(
                  context,
                  ref,
                  source: ImageSource.gallery,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _pickAvatarAndUpdate(
                  context,
                  ref,
                  source: ImageSource.camera,
                );
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      );
    },
  );
}
