import 'package:boomerang/features/feed/presentation/boomerang_viewer_page.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('No saved boomerangs yet'));
        }
        return GridView.builder(
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
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BoomerangViewerPage(
                      id: id,
                      data: data,
                    ),
                  ),
                );
              },
              onLongPress: () async {
                await ref.read(savedRepoProvider).remove(
                  userId: me.uid,
                  boomerangId: id,
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Removed from saved')),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12.r),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageUrl.isNotEmpty)
                      Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Container(color: const Color(0xFFF2F2F2)),
                      )
                    else
                      Container(color: const Color(0xFFF2F2F2)),
                    if (videoUrl.isNotEmpty && imageUrl.isEmpty)
                      Center(
                        child: Icon(Icons.play_circle_filled,
                            size: 24, color: Colors.white70),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}


