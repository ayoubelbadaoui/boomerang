import 'package:boomerang/features/profile/application/user_boomerangs_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:developer' show log;
import 'package:boomerang/features/feed/presentation/boomerang_viewer_page.dart';

class UserBoomerangsGrid extends ConsumerStatefulWidget {
  const UserBoomerangsGrid({super.key});

  @override
  ConsumerState<UserBoomerangsGrid> createState() => _UserBoomerangsGridState();
}

class _UserBoomerangsGridState extends ConsumerState<UserBoomerangsGrid> {
  @override
  void initState() {
    super.initState();
    // Prefetch on first mount
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final value = ref.read(userBoomerangsControllerProvider).valueOrNull;
      if (value == null || value.docs.isEmpty) {
        ref.read(userBoomerangsControllerProvider.notifier).fetchNext();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(userBoomerangsControllerProvider);
    return asyncState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) {
        log(
          'User boomerangs grid error',
          name: 'UserBoomerangsGrid',
          error: e,
          stackTrace: st,
        );
        return Center(child: Text('Failed to load posts: $e'));
      },
      data: (s) {
        if (s.docs.isEmpty && s.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.docs.isEmpty) {
          return const Center(child: Text('No posts yet'));
        }
        final spacing = 4.w;
        return Column(
          children: [
            GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: s.docs.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) {
                final doc = s.docs[index];
                final data = doc.data();
                final id = doc.id;
                final imageUrl = data['imageUrl'] as String?;
                final videoUrl = data['videoUrl'] as String?;
                return InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BoomerangViewerPage(id: id, data: data),
                      ),
                    );
                  },
                  child: _GridTile(imageUrl: imageUrl, videoUrl: videoUrl),
                );
              },
            ),
            SizedBox(height: 8.h),
            if (s.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (s.hasMore)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed:
                      () =>
                          ref
                              .read(userBoomerangsControllerProvider.notifier)
                              .fetchNext(),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.black, width: 1),
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    shape: StadiumBorder(
                      side: BorderSide(color: Colors.black, width: 1.w),
                    ),
                  ),
                  child: Text(
                    'Load more',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({required this.imageUrl, required this.videoUrl});
  final String? imageUrl;
  final String? videoUrl;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (imageUrl != null && imageUrl!.isNotEmpty)
          Image.network(
            imageUrl!,
            fit: BoxFit.cover,
            errorBuilder:
                (_, __, ___) => Container(color: const Color(0xFFF2F2F2)),
          )
        else
          Container(color: const Color(0xFFF2F2F2)),
        Positioned(
          right: 6.w,
          bottom: 6.h,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(8.r),
            ),
            padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 16,
                ),
                SizedBox(width: 2.w),
                Text(
                  videoUrl != null ? 'Video' : 'Post',
                  style: TextStyle(color: Colors.white, fontSize: 11.sp),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
