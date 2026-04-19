import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class PostsGrid extends StatelessWidget {
  const PostsGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final double spacing = 4.w;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: 1,
      ),
      itemCount: 12,
      itemBuilder: (context, index) {
        return Container(
          color: const Color(0xFFF2F2F2),
          child: const Center(
            child: Icon(
              Icons.play_arrow_rounded,
              color: Colors.black26,
              size: 28,
            ),
          ),
        );
      },
    );
  }
}
