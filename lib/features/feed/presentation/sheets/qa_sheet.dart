import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class QASheet extends StatelessWidget {
  const QASheet({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      const _QAItem(
        'Benny Spanbauer',
        'What is your favorite fruit?',
        736,
        'https://i.pravatar.cc/100?img=1',
      ),
      const _QAItem(
        'Hannah Burress',
        'Do you have any pet peeves?',
        662,
        'https://i.pravatar.cc/100?img=2',
      ),
      const _QAItem(
        'Aileen Fullbright',
        'Have you ever burnt your hair?',
        489,
        'https://i.pravatar.cc/100?img=3',
      ),
      const _QAItem(
        'Rodolfo Goode',
        'Have you ever been to Asia?',
        364,
        'https://i.pravatar.cc/100?img=4',
      ),
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            SizedBox(height: 16.h),
            Center(
              child: Text(
                'Question & Answer',
                style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.w800),
              ),
            ),
            SizedBox(height: 16.h),
            const Divider(),
            SizedBox(height: 12.h),
            Text(
              '3,378 questions from guests',
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8.h),
            ...items.map((e) => _QAListTile(item: e)).toList(),
            SizedBox(height: 12.h),
            _AskBar(),
          ],
        ),
      ),
    );
  }
}

class _AskBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F6F6),
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: const Text(
              'Ask a question...',
              style: TextStyle(color: Colors.black54),
            ),
          ),
        ),
        SizedBox(width: 12.w),
        CircleAvatar(
          radius: 28.r,
          backgroundColor: Colors.black,
          child: const Icon(Icons.send, color: Colors.white),
        ),
      ],
    );
  }
}

class _QAItem {
  final String author;
  final String question;
  final int likes;
  final String avatar;
  const _QAItem(this.author, this.question, this.likes, this.avatar);
}

class _QAListTile extends StatelessWidget {
  const _QAListTile({required this.item});
  final _QAItem item;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 28.r,
            backgroundImage: NetworkImage(item.avatar),
            backgroundColor: const Color(0xFFF2F2F2),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.author,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16.sp,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(item.question, style: TextStyle(fontSize: 16.sp)),
              ],
            ),
          ),
          Column(
            children: [
              const Icon(Icons.favorite_border),
              SizedBox(height: 6.h),
              Text(
                '${item.likes}',
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ],
      ),
    );
  }
}






