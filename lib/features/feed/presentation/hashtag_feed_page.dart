import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boomerang/features/feed/presentation/boomerang_viewer_page.dart';
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
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(16.w),
                child: Text(
                  'Failed to load posts for #$tag.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
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
              final id = docs[i].id;
              final d = docs[i].data();
              final poster = (d['imageUrl'] ?? '') as String?;
              final videoUrl = (d['videoUrl'] ?? '') as String?;
              return InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BoomerangViewerPage(id: id, data: d),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18.r),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (poster != null && poster.isNotEmpty)
                        Image.network(poster, fit: BoxFit.cover)
                      else
                        Container(color: const Color(0xFFEEEEEE)),
                      if ((poster == null || poster.isEmpty) &&
                          (videoUrl != null && videoUrl.isNotEmpty))
                        Center(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(24.r),
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: 8.w,
                              vertical: 4.h,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Video',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
