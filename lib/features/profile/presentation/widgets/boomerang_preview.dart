import 'package:boomerang/core/utils/color_opacity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';

Future<void> showBoomerangPreview(
  BuildContext context, {
  required String? videoUrl,
  String? posterUrl,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Preview',
    barrierColor: Colors.black.fade(0.85),
    pageBuilder: (context, _, __) {
      return _PreviewContent(videoUrl: videoUrl, posterUrl: posterUrl);
    },
    transitionDuration: const Duration(milliseconds: 200),
    transitionBuilder: (context, anim, _, child) {
      return FadeTransition(opacity: anim, child: child);
    },
  );
}

class _PreviewContent extends StatefulWidget {
  const _PreviewContent({required this.videoUrl, this.posterUrl});
  final String? videoUrl;
  final String? posterUrl;

  @override
  State<_PreviewContent> createState() => _PreviewContentState();
}

class _PreviewContentState extends State<_PreviewContent> {
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
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16.r),
                child:
                    _controller != null && _controller!.value.isInitialized
                        ? FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _controller!.value.size.width,
                            height: _controller!.value.size.height,
                            child: VideoPlayer(_controller!),
                          ),
                        )
                        : (widget.posterUrl != null
                            ? Image.network(
                              widget.posterUrl!,
                              fit: BoxFit.cover,
                            )
                            : Container(color: Colors.black)),
              ),
            ),
          ),
          Positioned(
            top: 24.h,
            right: 24.w,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
