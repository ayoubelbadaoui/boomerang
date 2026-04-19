import 'package:boomerang/core/widgets/boomerang_overlay.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';

class SingleBoomerangPage extends ConsumerStatefulWidget {
  const SingleBoomerangPage({super.key, required this.boomerangId});

  final String boomerangId;

  @override
  ConsumerState<SingleBoomerangPage> createState() =>
      _SingleBoomerangPageState();
}

class _SingleBoomerangPageState extends ConsumerState<SingleBoomerangPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();
    _loadPost();
  }

  Future<void> _loadPost() async {
    try {
      final repo = ref.read(boomerangRepoProvider);
      final result = await repo.fetchBoomerangById(widget.boomerangId);
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _loading = false;
          _error = 'This boomerang is no longer available.';
        });
        return;
      }
      final (_, data) = result;
      setState(() {
        _data = data;
        _loading = false;
      });
      _initVideo(data['videoUrl'] as String?);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load post.';
      });
    }
  }

  void _initVideo(String? url) {
    if (url == null || url.isEmpty) return;
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _videoController = controller;
    controller
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          controller.setLooping(true);
          controller.play();
        }
      })
      ..setVolume(0);
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.white54, size: 56.sp),
              SizedBox(height: 16.h),
              Text(
                _error!,
                style: TextStyle(color: Colors.white70, fontSize: 16.sp),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 24.h),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      );
    }

    final data = _data!;
    final imageUrl = data['imageUrl'] as String?;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_videoController != null && _videoController!.value.isInitialized)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _videoController!.value.size.width,
              height: _videoController!.value.size.height,
              child: VideoPlayer(_videoController!),
            ),
          )
        else if (imageUrl != null && imageUrl.isNotEmpty)
          Image.network(imageUrl, fit: BoxFit.cover)
        else
          const ColoredBox(color: Colors.black),
        BoomerangOverlay(
          boomerangId: widget.boomerangId,
          data: data,
        ),
      ],
    );
  }
}
