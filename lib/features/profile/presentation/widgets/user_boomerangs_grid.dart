import 'package:boomerang/core/utils/color_opacity.dart';
import 'package:boomerang/features/profile/application/user_boomerangs_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:developer' show log;
import 'package:boomerang/features/profile/presentation/profile_reels_page.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

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

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String boomerangId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Boomerang'),
        content: const Text(
          'Are you sure you want to delete this boomerang? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(userBoomerangsControllerProvider.notifier)
          .deleteBoomerang(boomerangId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Boomerang deleted')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    }
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
        return Column(
          children: [
            MasonryGridView.count(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: s.docs.length,
              crossAxisCount: 2,
              mainAxisSpacing: 12.h,
              crossAxisSpacing: 12.w,
              itemBuilder: (context, index) {
                final doc = s.docs[index];
                final data = doc.data();
                final imageUrl = data['imageUrl'] as String?;
                final videoUrl = data['videoUrl'] as String?;
                final aspectRatio = index.isEven ? 9 / 14 : 9 / 11;
                return InkWell(
                  onTap: () {
                    final items = s.docs
                        .map((d) => (id: d.id, data: d.data()))
                        .toList();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProfileReelsPage(
                          initialItems: items,
                          initialIndex: index,
                          hasMore: s.hasMore,
                          onLoadMore: () => ref
                              .read(userBoomerangsControllerProvider.notifier)
                              .fetchNext(),
                        ),
                      ),
                    );
                  },
                  onLongPress: () => _confirmDelete(context, ref, doc.id),
                  child: AspectRatio(
                    aspectRatio: aspectRatio,
                    child: _GridTile(imageUrl: imageUrl, videoUrl: videoUrl),
                  ),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(12.r),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null && imageUrl!.isNotEmpty)
            Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              cacheWidth: (180 * MediaQuery.devicePixelRatioOf(context)).round(),
              errorBuilder:
                  (_, __, ___) => Container(color: const Color(0xFFF2F2F2)),
            )
          else
            Container(color: const Color(0xFFF2F2F2)),
          if (videoUrl != null && videoUrl!.isNotEmpty)
            Positioned(
              left: 8.w,
              bottom: 8.h,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.fade(0.55),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.play_circle_filled,
                      size: 14,
                      color: Colors.white70,
                    ),
                    SizedBox(width: 4.w),
                    Text(
                      'Preview',
                      style: TextStyle(color: Colors.white, fontSize: 12.sp),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
