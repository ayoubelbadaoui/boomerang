import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';

class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  static const String routeName = '/home_tab';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = ref.watch(boomerangRepoProvider).watchBoomerangs();
    return StreamBuilder(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('No boomerangs yet'));
        }
        return ListView.separated(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 100.h),
          itemCount: docs.length,
          separatorBuilder: (_, __) => SizedBox(height: 16.h),
          itemBuilder: (context, i) {
            final data = docs[i].data();
            return _BoomerangCard(data: data);
          },
        );
      },
    );
  }
}

class _BoomerangCard extends StatelessWidget {
  const _BoomerangCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final handle =
        '@${(data['userName'] ?? 'user').toString().replaceAll(' ', '_').toLowerCase()}';
    final avatar = data['userAvatar'] as String?;
    final image = data['imageUrl'] as String?; // optional poster
    final video = data['videoUrl'] as String?;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24.r),
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              child: _BoomerangMedia(videoUrl: video, posterUrl: image),
            ),
            Positioned(
              left: 12.w,
              top: 12.h,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14.r,
                    backgroundImage:
                        avatar != null ? NetworkImage(avatar) : null,
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    handle,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.sp,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 12.w,
              top: 12.h,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: EdgeInsets.all(8.r),
                child: const Icon(Icons.bookmark_border, color: Colors.white),
              ),
            ),
            Positioned(
              left: 12.w,
              bottom: 12.h,
              child: Row(
                children: [
                  _CircleBtn(icon: Icons.chat_bubble_outline),
                  SizedBox(width: 8.w),
                  _CircleBtn(icon: Icons.reply_outlined),
                ],
              ),
            ),
            Positioned(
              right: 12.w,
              bottom: 12.h,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: EdgeInsets.all(8.r),
                child: const Icon(Icons.favorite_border, color: Colors.white),
              ),
            ),
            Positioned(
              left: 12.w,
              bottom: 52.h,
              child: Row(
                children: [
                  Text(
                    handle,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.sp,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    'Description',
                    style: TextStyle(color: Colors.white70, fontSize: 14.sp),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({required this.icon});
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
      ),
      padding: EdgeInsets.all(8.r),
      child: Icon(icon, color: Colors.white),
    );
  }
}

class _BoomerangMedia extends StatefulWidget {
  const _BoomerangMedia({required this.videoUrl, required this.posterUrl});
  final String? videoUrl;
  final String? posterUrl;

  @override
  State<_BoomerangMedia> createState() => _BoomerangMediaState();
}

class _BoomerangMediaState extends State<_BoomerangMedia> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.videoUrl != null) {
      _controller = VideoPlayerController.networkUrl(
          Uri.parse(widget.videoUrl!),
        )
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() {});
          _controller?.setLooping(true);
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
    if (_controller != null && _controller!.value.isInitialized) {
      return FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: _controller!.value.size.width,
          height: _controller!.value.size.height,
          child: VideoPlayer(_controller!),
        ),
      );
    }
    if (widget.posterUrl != null) {
      return Image.network(widget.posterUrl!, fit: BoxFit.cover);
    }
    return Container(color: Colors.black12);
  }
}
