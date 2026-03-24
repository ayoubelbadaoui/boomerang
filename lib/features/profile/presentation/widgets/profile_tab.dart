import 'package:boomerang/features/profile/application/profile_controller.dart';
import 'package:boomerang/features/profile/application/user_boomerangs_controller.dart';
import 'package:boomerang/features/profile/presentation/widgets/account_switcher_sheet.dart';
import 'package:boomerang/features/profile/presentation/widgets/edit_profile_page.dart';
import 'package:boomerang/features/profile/presentation/widgets/mode_icon.dart';
import 'package:boomerang/features/profile/presentation/widgets/user_boomerangs_grid.dart';
import 'package:boomerang/features/profile/presentation/widgets/stat.dart';
import 'package:boomerang/features/profile/presentation/sheets/follow_list_sheet.dart';
import 'package:boomerang/features/profile/presentation/settings/settings_page.dart';
import 'package:boomerang/features/profile/presentation/widgets/saved_boomerangs_grid.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/core/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'dart:developer' show log;

final profileSectionIndexProvider = StateProvider<int>((ref) => 0);

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
          onPressed: () => showAccountSwitcher(context, ref),
          icon: Icon(
            Icons.person_add_alt_1_outlined,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
        title: GestureDetector(
          onTap: () => showAccountSwitcher(context, ref),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              profile.when(
                data:
                    (p) => Text(
                      (p?.fullName.isNotEmpty == true
                          ? p!.fullName
                          : p?.nickname ?? ''),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const Text('Profile'),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {
              context.push(SettingsPage.routeName);
            },
            icon: const Icon(Icons.settings_outlined, color: Colors.black),
          ),
        ],
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Failed to load profile')),
        data:
            (p) => RefreshIndicator(
              color: Colors.black,
              onRefresh: () async {
                final uid = p?.uid ?? '';
                ref.invalidate(profileControllerProvider);
                ref.invalidate(currentUserProfileProvider);
                if (uid.isNotEmpty) {
                  ref.invalidate(userBoomerangsCountProvider(uid));
                  ref.invalidate(followersCountProvider(uid));
                  ref.invalidate(followingCountProvider(uid));
                  ref.invalidate(userTotalLikesProvider(uid));
                }
                await ref
                    .read(userBoomerangsControllerProvider.notifier)
                    .refresh();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                        AppAvatar(url: p?.avatarUrl, size: 96.r),
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
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Builder(
                        builder: (_) {
                          final uid = p?.uid ?? '';
                          final postsCount = ref.watch(
                            userBoomerangsCountProvider(uid),
                          );
                          final value = postsCount.maybeWhen(
                            data: (v) => '$v',
                            orElse: () => '0',
                          );
                          return Stat(value: value, label: 'Bmg.');
                        },
                      ),
                      Builder(
                        builder: (_) {
                          final uid = p?.uid ?? '';
                          final followers = ref.watch(
                            followersCountProvider(uid),
                          );
                          final followersText = followers.maybeWhen(
                            data: (v) => '$v',
                            orElse: () => '0',
                          );
                          return Stat(
                            value: followersText,
                            label: 'Followers',
                            onTap:
                                () => showModalBottomSheet<void>(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.white,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(24),
                                    ),
                                  ),
                                  builder:
                                      (_) => SizedBox(
                                        height: 500,
                                        child: FollowListSheet(
                                          mode: FollowMode.followers,
                                          userId: uid,
                                        ),
                                      ),
                                ),
                          );
                        },
                      ),
                      Builder(
                        builder: (_) {
                          final uid = p?.uid ?? '';
                          final following = ref.watch(
                            followingCountProvider(uid),
                          );
                          final followingText = following.maybeWhen(
                            data: (v) => '$v',
                            orElse: () => '0',
                          );
                          return Stat(
                            value: followingText,
                            label: 'Following',
                            onTap:
                                () => showModalBottomSheet<void>(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.white,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(24),
                                    ),
                                  ),
                                  builder:
                                      (_) => SizedBox(
                                        height: 500,
                                        child: FollowListSheet(
                                          mode: FollowMode.following,
                                          userId: uid,
                                        ),
                                      ),
                                ),
                          );
                        },
                      ),
                      Builder(
                        builder: (_) {
                          final uid = p?.uid ?? '';
                          final totalLikes = ref.watch(
                            userTotalLikesProvider(uid),
                          );
                          final value = totalLikes.maybeWhen(
                            data: (v) => '$v',
                            orElse: () => '0',
                          );
                          return Stat(value: value, label: 'Likes');
                        },
                      ),
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
                    children: [
                      GestureDetector(
                        onTap:
                            () =>
                                ref
                                    .read(profileSectionIndexProvider.notifier)
                                    .state = 0,
                        child: ModeIcon(
                          icon: Icons.grid_on_rounded,
                          active: ref.watch(profileSectionIndexProvider) == 0,
                        ),
                      ),
                      GestureDetector(
                        onTap:
                            () =>
                                ref
                                    .read(profileSectionIndexProvider.notifier)
                                    .state = 1,
                        child: ModeIcon(
                          icon: Icons.bookmark_border_rounded,
                          active: ref.watch(profileSectionIndexProvider) == 1,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12.h),
                  Divider(height: 1.h, color: Colors.black12),
                  SizedBox(height: 12.h),
                  Builder(
                    builder: (_) {
                      final section = ref.watch(profileSectionIndexProvider);
                      if (section == 0) return const UserBoomerangsGrid();
                      return const SavedBoomerangsGrid();
                    },
                  ),
                  SizedBox(height: 80.h),
                ],
              ),
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
