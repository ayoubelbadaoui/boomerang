import 'dart:async';
import 'dart:io';

import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

class BoomerangEditorPage extends ConsumerStatefulWidget {
  const BoomerangEditorPage({super.key, required this.inputFile});
  final File inputFile;

  @override
  ConsumerState<BoomerangEditorPage> createState() =>
      _BoomerangEditorPageState();
}

class _BoomerangEditorPageState extends ConsumerState<BoomerangEditorPage> {
  VideoPlayerController? _controller;
  Timer? _reverseTimer;
  bool _processing = false;
  final _caption = TextEditingController();

  double _segmentSeconds = 1.6;
  double _totalSeconds = 6.0;
  double _speed = 1.0;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.inputFile)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _controller?.setLooping(false);
        _controller?.setVolume(0.0);
        _playForward();
      });
  }

  void _disposePlaybackTimers() {
    _reverseTimer?.cancel();
    _reverseTimer = null;
  }

  void _playForward() {
    _disposePlaybackTimers();
    _controller?.seekTo(Duration.zero);
    _controller?.setPlaybackSpeed(_speed);
    _controller?.play();
    _controller?.addListener(_tick);
  }

  void _startReverse() {
    _controller?.removeListener(_tick);
    _controller?.pause();
    _disposePlaybackTimers();
    _reverseTimer = Timer.periodic(const Duration(milliseconds: 33), (t) {
      final c = _controller;
      if (c == null || !c.value.isInitialized) {
        t.cancel();
        return;
      }
      final pos = c.value.position;
      final stepMs = (33 * _speed).clamp(1, 200).toInt();
      final next = pos - Duration(milliseconds: stepMs);
      if (next <= Duration.zero) {
        c.seekTo(Duration.zero);
        t.cancel();
        Future.microtask(_playForward);
      } else {
        c.seekTo(next);
      }
    });
  }

  void _tick() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final seg = Duration(milliseconds: (_segmentSeconds * 1000).round());
    final pos = c.value.position;
    if (pos >= seg) {
      _startReverse();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_tick);
    _disposePlaybackTimers();
    _controller?.dispose();
    _caption.dispose();
    super.dispose();
  }

  Future<void> _onCreate() async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      final processor = ref.read(boomerangProcessorProvider);
      final outPath = await processor.makeBoomerang(
        widget.inputFile.path,
        segmentSeconds: _segmentSeconds,
        totalDurationSeconds: _totalSeconds,
        speed: _speed,
      );

      final storage = ref.read(storageProvider);
      final path = 'boomerangs/${DateTime.now().millisecondsSinceEpoch}.mp4';
      final task = await storage.ref(path).putFile(File(outPath));
      final url = await task.ref.getDownloadURL();

      final me = ref.read(currentUserProfileProvider).value;
      if (me == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Please log in first.')));
        return;
      }

      // Parse hashtags from caption
      final caption = _caption.text.trim();
      final tags = <String>{};
      final re = RegExp(r'(?:#)([A-Za-z0-9_]{1,30})');
      for (final m in re.allMatches(caption)) {
        final t = m.group(1);
        if (t != null && t.isNotEmpty) tags.add(t.toLowerCase());
      }

      await ref
          .read(boomerangRepoProvider)
          .createBoomerangPost(
            userId: me.uid,
            userName: me.nickname.isNotEmpty ? me.nickname : me.fullName,
            userAvatar: me.avatarUrl,
            videoUrl: url,
            imageUrl: null,
            caption: caption.isEmpty ? null : caption,
            hashtags: tags.isEmpty ? null : tags.toList(),
          );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Boomerang created')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller?.value.isInitialized == true;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Edit Boomerang'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child:
                  ready
                      ? FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: _controller!.value.size.width,
                          height: _controller!.value.size.height,
                          child: VideoPlayer(_controller!),
                        ),
                      )
                      : const CircularProgressIndicator(color: Colors.white),
            ),
          ),
          _Controls(
            segmentSeconds: _segmentSeconds,
            onSegmentChanged: (v) {
              setState(() => _segmentSeconds = v);
            },
            totalSeconds: _totalSeconds,
            onTotalChanged: (v) {
              setState(() => _totalSeconds = v);
            },
            speed: _speed,
            onSpeedChanged: (v) {
              setState(() {
                _speed = v;
                // apply to live preview
                _controller?.setPlaybackSpeed(_speed);
              });
            },
            onCreate: _processing ? null : _onCreate,
            processing: _processing,
            caption: _caption,
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.segmentSeconds,
    required this.onSegmentChanged,
    required this.totalSeconds,
    required this.onTotalChanged,
    required this.speed,
    required this.onSpeedChanged,
    required this.onCreate,
    required this.processing,
    required this.caption,
  });

  final double segmentSeconds;
  final ValueChanged<double> onSegmentChanged;
  final double totalSeconds;
  final ValueChanged<double> onTotalChanged;
  final double speed;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback? onCreate;
  final bool processing;
  final TextEditingController caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chipTimes = <double>[3, 6, 10];
    final speedOptions = <double>[0.5, 1.0, 1.5, 2.0];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Caption', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          TextField(
            controller: caption,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: 'Write a caption… use #hashtags',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text('Clip length', style: theme.textTheme.titleMedium),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: segmentSeconds.clamp(0.8, 3.0),
                  min: 0.8,
                  max: 3.0,
                  divisions: 11,
                  label: '${segmentSeconds.toStringAsFixed(1)}s',
                  onChanged: onSegmentChanged,
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  '${segmentSeconds.toStringAsFixed(1)}s',
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Total duration', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children:
                chipTimes
                    .map(
                      (t) => ChoiceChip(
                        label: Text('${t.toStringAsFixed(0)}s'),
                        selected: totalSeconds.round() == t.round(),
                        onSelected: (_) => onTotalChanged(t),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 12),
          Text('Speed', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children:
                speedOptions
                    .map(
                      (s) => ChoiceChip(
                        label: Text('${s}x'),
                        selected: (speed - s).abs() < 0.01,
                        onSelected: (_) => onSpeedChanged(s),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onCreate,
              child: Text(processing ? 'Processing…' : 'Create Boomerang'),
            ),
          ),
        ],
      ),
    );
  }
}
