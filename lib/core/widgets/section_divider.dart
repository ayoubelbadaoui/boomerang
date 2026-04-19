import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class SectionDivider extends StatelessWidget {
  const SectionDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          child: Text(label, style: TextStyle(fontSize: 14.sp)),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
