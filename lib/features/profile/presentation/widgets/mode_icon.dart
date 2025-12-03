import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ModeIcon extends StatelessWidget {
  const ModeIcon({super.key, required this.icon, this.active = false});
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


