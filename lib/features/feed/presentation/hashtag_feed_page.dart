import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/moderation/application/moderation_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boomerang/features/feed/presentation/boomerang_viewer_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

class HashtagFeedPage extends ConsumerWidget {
  const HashtagFeedPage({super.key, required this.tag});
  final String tag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = ref.watch(boomerangRepoProvider).watchByHashtag(tag);
    final blockedSet =
        ref.watch(blockedUsersProvider).value?.toSet() ?? const <String>{};
    final myUid = ref.watch(firebaseAuthProvider).currentUser?.uid;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          '#$tag',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
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
          final allDocs = snapshot.data!.docs;
          final docs = allDocs.where((d) {
            final data = d.data();
            final uid = (data['userId'] ?? '') as String;
            if (blockedSet.contains(uid)) return false;
            if (data['ownerIsPrivate'] == true && uid != myUid) return false;
            return true;
          }).toList();
          if (docs.isEmpty) {
            return const Center(child: Text('No posts for this hashtag yet'));
          }
          return MasonryGridView.count(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            crossAxisCount: 2,
            mainAxisSpacing: 16.h,
            crossAxisSpacing: 16.w,
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final id = docs[i].id;
              final d = docs[i].data();
              final poster = (d['imageUrl'] ?? '') as String?;
              final videoUrl = (d['videoUrl'] ?? '') as String?;
              final aspectRatio = i.isEven ? 9 / 13 : 9 / 10;
              return InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BoomerangViewerPage(id: id, data: d),
                    ),
                  );
                },
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18.r),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (poster != null && poster.isNotEmpty)
                          Image.network(
                            poster,
                            fit: BoxFit.cover,
                            cacheWidth: (180 * MediaQuery.devicePixelRatioOf(context)).round(),
                          )
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
                ),
              );
            },
          );
        },
      ),
    );
  }
}
