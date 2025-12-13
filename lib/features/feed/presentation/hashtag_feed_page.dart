import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class HashtagFeedPage extends ConsumerWidget {
  const HashtagFeedPage({super.key, required this.tag});
  final String tag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = ref.watch(boomerangRepoProvider).watchByHashtag(tag);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          '#$tag',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20.sp),
        ),
      ),
      body: StreamBuilder(
        stream: stream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('No posts for this hashtag yet'));
          }
          return GridView.builder(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16.h,
              crossAxisSpacing: 16.w,
              childAspectRatio: 3 / 4,
            ),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final poster = (d['imageUrl'] ?? '') as String?;
              return ClipRRect(
                borderRadius: BorderRadius.circular(18.r),
                child:
                    poster != null && poster.isNotEmpty
                        ? Image.network(poster, fit: BoxFit.cover)
                        : Container(color: const Color(0xFFF2F2F2)),
              );
            },
          );
        },
      ),
    );
  }
}
