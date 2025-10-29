import 'package:video_player/video_player.dart';
import 'package:flutter/material.dart';

class BoomerangVideoPlayer extends StatefulWidget {
  final String videoUrl; // Or path to local asset

  const BoomerangVideoPlayer({Key? key, required this.videoUrl})
    : super(key: key);

  @override
  _BoomerangVideoPlayerState createState() => _BoomerangVideoPlayerState();
}

class _BoomerangVideoPlayerState extends State<BoomerangVideoPlayer> {
  late VideoPlayerController _controller;
  late Future<void> _initializeVideoPlayerFuture;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
    ); // Or VideoPlayerController.asset()
    _initializeVideoPlayerFuture = _controller.initialize().then((_) {
      _controller.setLooping(false); // We'll manage looping manually
      _controller.play();
      _controller.addListener(_videoListener);
    });
  }

  void _videoListener() {
    if (_controller.value.position >= _controller.value.duration &&
        _controller.value.isPlaying) {
      // Video finished playing forward, now play in reverse
      _controller.seekTo(_controller.value.duration);
      _controller.setPlaybackSpeed(-1.0); // Play in reverse
      _controller.play();
    } else if (_controller.value.position <= Duration.zero &&
        _controller.value.isPlaying &&
        _controller.value.playbackSpeed < 0) {
      // Video finished playing in reverse, now play forward
      _controller.seekTo(Duration.zero);
      _controller.setPlaybackSpeed(1.0); // Play forward
      _controller.play();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_videoListener);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initializeVideoPlayerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          );
        } else {
          return Center(child: CircularProgressIndicator());
        }
      },
    );
  }
}
