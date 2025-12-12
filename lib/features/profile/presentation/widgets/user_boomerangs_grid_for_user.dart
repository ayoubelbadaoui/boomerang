import 'package:boomerang/features/profile/application/user_boomerangs_by_user_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:boomerang/features/feed/presentation/boomerang_viewer_page.dart';
import 'package:video_player/video_player.dart';

class UserBoomerangsGridForUser extends ConsumerStatefulWidget {
  const UserBoomerangsGridForUser({super.key, required this.userId});
  final String userId;

  @override
  ConsumerState<UserBoomerangsGridForUser> createState() =>
      _UserBoomerangsGridForUserState();
}

class _UserBoomerangsGridForUserState
    extends ConsumerState<UserBoomerangsGridForUser> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final value = ref
          .read(userBoomerangsByUserControllerProvider(widget.userId))
          .valueOrNull;
      if (value == null || value.docs.isEmpty) {
        ref
            .read(userBoomerangsByUserControllerProvider(widget.userId).notifier)
            .fetchNext();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncState =
        ref.watch(userBoomerangsByUserControllerProvider(widget.userId));
    return asyncState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load posts: $e')),
      data: (s) {
        if (s.docs.isEmpty && s.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.docs.isEmpty) {
          return const Center(child: Text('No posts yet'));
        }
        return Column(
          children: [
            GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: s.docs.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 16.h,
                crossAxisSpacing: 16.w,
                childAspectRatio: 3 / 4,
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
                        builder:
                            (_) => BoomerangViewerPage(id: id, data: data),
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
                  onPressed: () => ref
                      .read(userBoomerangsByUserControllerProvider(widget.userId)
                          .notifier)
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

class _GridTile extends StatefulWidget {
  const _GridTile({required this.imageUrl, required this.videoUrl});
  final String? imageUrl;
  final String? videoUrl;

  @override
  State<_GridTile> createState() => _GridTileState();
}

class _GridTileState extends State<_GridTile> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.videoUrl != null && widget.videoUrl!.isNotEmpty) {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl!),
      )
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() {});
          _controller?.setLooping(true);
          _controller?.setVolume(0.0);
          _controller?.play();
        });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? imageUrl = widget.imageUrl;
    final String? videoUrl = widget.videoUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12.r),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_controller != null && _controller!.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            )
          else if (imageUrl != null && imageUrl.isNotEmpty)
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder:
                  (_, __, ___) => Container(color: const Color(0xFFF2F2F2)),
            )
          else
            Container(color: const Color(0xFFF2F2F2)),
          Positioned(
            left: 8.w,
            bottom: 8.h,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(12.r),
              ),
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_circle_filled,
                      size: 14, color: Colors.white70),
                  SizedBox(width: 4.w),
                  Text(
                    videoUrl != null ? 'Preview' : 'Post',
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






