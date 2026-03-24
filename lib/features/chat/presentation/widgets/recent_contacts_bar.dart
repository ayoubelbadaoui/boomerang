import 'package:boomerang/core/widgets/avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:boomerang/features/profile/domain/user_profile.dart';

class RecentContactsBar extends StatelessWidget {
  const RecentContactsBar({
    super.key,
    required this.profiles,
    required this.onTap,
  });

  final List<UserProfile> profiles;
  final ValueChanged<UserProfile> onTap;

  @override
  Widget build(BuildContext context) {
    if (profiles.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Text('Recently', style: theme.textTheme.titleSmall),
        ),
        SizedBox(height: 12.h),
        SizedBox(
          height: 86.h,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            itemCount: profiles.length,
            separatorBuilder: (_, __) => SizedBox(width: 16.w),
            itemBuilder: (context, index) {
              final profile = profiles[index];
              return GestureDetector(
                onTap: () => onTap(profile),
                child: SizedBox(
                  width: 64.w,
                  child: Column(
                    children: [
                      AppAvatar(url: profile.avatarUrl, size: 56.r),
                      SizedBox(height: 6.h),
                      Text(
                        profile.fullName.split(' ').first,
                        style: theme.textTheme.labelSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
