import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ListItem extends StatelessWidget {
  const ListItem({super.key, required this.label, required this.controller});
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
