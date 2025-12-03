import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ProfilePreviewSheet extends StatelessWidget {
  const ProfilePreviewSheet({
    super.key,
    required this.handle,
    required this.avatarUrl,
    this.subtitle,
  });
  final String handle;
  final String? avatarUrl;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 5,
              margin: EdgeInsets.only(bottom: 16.h),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            CircleAvatar(
              radius: 44.r,
              backgroundImage:
                  avatarUrl != null ? NetworkImage(avatarUrl!) : null,
              backgroundColor: const Color(0xFFF2F2F2),
            ),
            SizedBox(height: 12.h),
            Text(
              handle,
              style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w800),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              SizedBox(height: 6.h),
              Text(
                subtitle!,
                style: TextStyle(color: Colors.black54, fontSize: 14.sp),
              ),
            ],
            SizedBox(height: 16.h),
            const Divider(),
            SizedBox(height: 12.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Stat(value: '823', label: 'Bmg.'),
                _Stat(value: '3.7M', label: 'Followers'),
                _Stat(value: '925', label: 'Following'),
                _Stat(value: '39M', label: 'Likes'),
              ],
            ),
            SizedBox(height: 16.h),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Follow'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Message'),
                    style: OutlinedButton.styleFrom(
                      shape: const StadiumBorder(),
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
        Text(label, style: TextStyle(color: Colors.black54, fontSize: 12.sp)),
      ],
    );
  }
}


