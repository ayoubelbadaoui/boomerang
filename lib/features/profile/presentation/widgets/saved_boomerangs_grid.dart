import 'package:boomerang/features/profile/presentation/profile_reels_page.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:boomerang/core/widgets/boomerang_grid_shimmers.dart';
import 'package:boomerang/core/widgets/boomerang_grid_thumbnail.dart';
import 'package:boomerang/core/widgets/instagram_shimmer.dart';

class SavedBoomerangsGrid extends ConsumerWidget {
  const SavedBoomerangsGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProfileProvider).value;
    if (me == null) {
      return const SizedBox.shrink();
    }
    final stream = ref.watch(savedRepoProvider).watchSaved(me.uid);
    return StreamBuilder(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SavedPostsGridShimmer();
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('No saved boomerangs yet'));
        }
        return ShimmerScope(
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: docs.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 16.h,
              crossAxisSpacing: 16.w,
              childAspectRatio: 3 / 4,
            ),
            itemBuilder: (context, index) {
              final d = docs[index];
              final data = d.data();
              final id = (data['boomerangId'] ?? d.id) as String;
              final imageUrl = (data['imageUrl'] as String?) ?? '';
              final videoUrl = (data['videoUrl'] as String?) ?? '';
              return GestureDetector(
                onTap: () {
                  final items = docs
                      .map((d) => (
                            id: ((d.data()['boomerangId'] ?? d.id) as String),
                            data: d.data(),
                          ))
                      .toList();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProfileReelsPage(
                        initialItems: items,
                        initialIndex: index,
                      ),
                    ),
                  );
                },
                onLongPress: () async {
                  await ref
                      .read(savedRepoProvider)
                      .remove(userId: me.uid, boomerangId: id);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Removed from saved')),
                  );
                },
                child: BoomerangGridThumbnail(
                  imageUrl: imageUrl.isNotEmpty ? imageUrl : null,
                  borderRadius: BorderRadius.circular(12.r),
                  cacheWidth: (180 * MediaQuery.devicePixelRatioOf(context)).round(),
                  phaseShift: index * 0.03,
                  overlays: [
                    if (videoUrl.isNotEmpty && imageUrl.isEmpty)
                      const Center(
                        child: Icon(
                          Icons.play_circle_filled,
                          size: 24,
                          color: Colors.white70,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
