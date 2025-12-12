import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ViewersSheet extends StatelessWidget {
  const ViewersSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final viewers = List.generate(
      8,
      (i) => _Viewer(
        'Viewer ${(i + 1)}',
        'https://i.pravatar.cc/100?img=${i + 10}',
      ),
    );
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              '3.6K Viewers',
              style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 12.h),
            const Divider(),
            SizedBox(height: 12.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F6F6),
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Colors.black38),
                  SizedBox(width: 8.w),
                  const Expanded(
                    child: Text(
                      'Search',
                      style: TextStyle(color: Colors.black38),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            ...viewers.map((v) => _ViewerTile(v)).toList(),
          ],
        ),
      ),
    );
  }
}

class _Viewer {
  final String name;
  final String avatar;
  const _Viewer(this.name, this.avatar);
}

class _ViewerTile extends StatelessWidget {
  const _ViewerTile(this.v);
  final _Viewer v;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          CircleAvatar(radius: 24.r, backgroundImage: NetworkImage(v.avatar)),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              v.name,
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
            ),
          ),
          OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
            child: const Text('Follow'),
          ),
        ],
      ),
    );
  }
}






