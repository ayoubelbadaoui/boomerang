import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/feed/presentation/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';

class _EditorFilter {
  const _EditorFilter(this.label, this.matrix, this.ffmpeg);
  final String label;
  final ColorFilter? matrix;
  final String? ffmpeg;
}

const _editorFilters = <_EditorFilter>[
  _EditorFilter('Original', null, null),
  _EditorFilter(
    'Warm',
    ColorFilter.matrix(<double>[
      1.2, 0.1, 0, 0, 15, 0, 1.08, 0, 0, 8, 0, 0, 0.9, 0, 0, 0, 0, 0, 1, 0,
    ]),
    'colorbalance=rs=0.15:gs=0.05:bs=-0.15,eq=brightness=0.04',
  ),
  _EditorFilter(
    'Cool',
    ColorFilter.matrix(<double>[
      0.9, 0, 0.08, 0, 0, 0, 0.95, 0.12, 0, 0, 0, 0.08, 1.15, 0, 15, 0, 0, 0, 1, 0,
    ]),
    'colorbalance=rs=-0.1:gs=0:bs=0.2,eq=brightness=0.02',
  ),
  _EditorFilter(
    'B&W',
    ColorFilter.matrix(<double>[
      0.33, 0.33, 0.33, 0, 0, 0.33, 0.33, 0.33, 0, 0, 0.33, 0.33, 0.33, 0, 0, 0, 0, 0, 1, 0,
    ]),
    'hue=s=0',
  ),
  _EditorFilter(
    'Vivid',
    ColorFilter.matrix(<double>[
      1.3, -0.1, 0, 0, 8, 0, 1.3, -0.1, 0, 8, -0.1, 0, 1.3, 0, 8, 0, 0, 0, 1, 0,
    ]),
    'eq=saturation=1.5:contrast=1.15:brightness=0.02',
  ),
];

class BoomerangEditorPage extends ConsumerStatefulWidget {
  const BoomerangEditorPage({
    super.key,
    required this.inputFile,
    this.initialSpeed = 1.0,
    this.videoFilter,
    this.previewFilter,
    this.mirrorVideo = false,
  });
  final File inputFile;
  final double initialSpeed;
  final String? videoFilter;
  final ColorFilter? previewFilter;
  final bool mirrorVideo;

  @override
  ConsumerState<BoomerangEditorPage> createState() =>
      _BoomerangEditorPageState();
}

class _BoomerangEditorPageState extends ConsumerState<BoomerangEditorPage>
    with TickerProviderStateMixin {
  VideoPlayerController? _controller;
  Timer? _reverseTimer;
  bool _processing = false;
  final _caption = TextEditingController();

  double _segmentSeconds = 1.6;
  late double _speed;
  String? _posterPath;
  bool _showPosterOverlay = true;
  late int _filterIdx;

  late final AnimationController _publishAnim;
  late final FixedExtentScrollController _filterScrollCtrl;

  @override
  void initState() {
    super.initState();
    _speed = widget.initialSpeed;
    _filterIdx = _resolveInitialFilter();
    _filterScrollCtrl = FixedExtentScrollController(initialItem: _filterIdx);
    _publishAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
    _controller = VideoPlayerController.file(widget.inputFile)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _controller?.setLooping(false);
        _controller?.setVolume(0.0);
        _playForward();
        _controller?.addListener(_onVideoTickForPoster);
      });
    _generateLocalPoster();
  }

  void _disposePlaybackTimers() {
    _reverseTimer?.cancel();
    _reverseTimer = null;
  }

  Future<void> _generateLocalPoster() async {
    try {
      final processor = ref.read(boomerangProcessorProvider);
      final path = await processor.generatePoster(
        widget.inputFile.path,
        targetWidth: 480,
      );
      if (!mounted) return;
      setState(() => _posterPath = path);
    } catch (_) {}
  }

  void _onVideoTickForPoster() {
    final c = _controller;
    if (c == null) return;
    final v = c.value;
    if (!v.isInitialized) return;
    final readyToReveal =
        !v.isBuffering && (v.isPlaying || v.position > Duration.zero);
    if (readyToReveal && _showPosterOverlay) {
      setState(() => _showPosterOverlay = false);
      c.removeListener(_onVideoTickForPoster);
    }
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
    final dur = c.value.duration;
    if (pos >= seg || (dur > Duration.zero && pos >= dur - const Duration(milliseconds: 50))) {
      _startReverse();
    }
  }

  int _resolveInitialFilter() {
    if (widget.videoFilter == null || widget.videoFilter!.isEmpty) return 0;
    final idx = _editorFilters.indexWhere((f) => f.ffmpeg == widget.videoFilter);
    return idx >= 0 ? idx : 0;
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    _controller?.removeListener(_tick);
    _controller?.removeListener(_onVideoTickForPoster);
    _disposePlaybackTimers();
    _controller?.dispose();
    _caption.dispose();
    _publishAnim.dispose();
    _filterScrollCtrl.dispose();
    super.dispose();
  }

  String? _buildColorFilter() {
    final f = _editorFilters[_filterIdx];
    return f.ffmpeg;
  }

  Future<void> _onCreate() async {
    if (_processing) return;
    FocusScope.of(context).unfocus();
    setState(() => _processing = true);
    _publishAnim.repeat();
    try {
      final processor = ref.read(boomerangProcessorProvider);
      final colorFilter = _buildColorFilter();

      String inputPath = widget.inputFile.path;
      if (widget.mirrorVideo) {
        inputPath = await processor.mirrorInput(inputPath);
      }

      final outPath = await processor.makeBoomerang(
        inputPath,
        segmentSeconds: _segmentSeconds,
        totalDurationSeconds: 6.0,
        speed: _speed,
        videoFilter: colorFilter,
      );

      final storage = ref.read(storageProvider);
      final path = 'boomerangs/${DateTime.now().millisecondsSinceEpoch}.mp4';
      final task = await storage.ref(path).putFile(File(outPath));
      final url = await task.ref.getDownloadURL();

      String? posterUrl;
      try {
        final posterPath = await processor.generatePoster(
          inputPath,
          videoFilter: colorFilter,
        );
        final posterRef = storage.ref(
          'boomerangs/posters/poster_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        final posterTask = await posterRef.putFile(File(posterPath));
        posterUrl = await posterTask.ref.getDownloadURL();
      } catch (_) {}

      final me = ref.read(currentUserProfileProvider).value;
      if (me == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in first.')),
        );
        return;
      }

      final caption = _caption.text.trim();
      final tags = <String>{};
      final re = RegExp(r'(?:#)([A-Za-z0-9_]{1,30})');
      for (final m in re.allMatches(caption)) {
        final t = m.group(1);
        if (t != null && t.isNotEmpty) tags.add(t.toLowerCase());
      }

      await ref.read(boomerangRepoProvider).createBoomerangPost(
            userId: me.uid,
            userName: me.nickname.isNotEmpty ? me.nickname : me.fullName,
            userAvatar: me.avatarUrl,
            videoUrl: url,
            imageUrl: posterUrl,
            caption: caption.isEmpty ? null : caption,
            hashtags: tags.isEmpty ? null : tags.toList(),
            ownerIsPrivate: me.isPrivate,
          );

      if (!mounted) return;
      ref.read(homeTabIndexProvider.notifier).state = 4;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Boomerang created')),
      );
    } catch (e, _) {
      if (!mounted) return;
      final isPluginMissing = e is MissingPluginException ||
          (e is PlatformException &&
              (e.message ?? '').contains('MissingPluginException'));
      final message = isPluginMissing
          ? 'Video processing is not available on this device.'
          : 'Failed: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      log('Editor ERROR: $e');
    } finally {
      if (mounted) {
        _publishAnim.stop();
        _publishAnim.reset();
        setState(() => _processing = false);
      }
    }
  }

  Widget _applyPreviewFilter({required Widget child}) {
    Widget result = child;
    if (widget.mirrorVideo) {
      result = Transform.flip(flipX: true, child: result);
    }
    final colorFilter = _editorFilters[_filterIdx].matrix;
    if (colorFilter != null) {
      result = ColorFiltered(colorFilter: colorFilter, child: result);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller?.value.isInitialized == true;
    final pad = MediaQuery.paddingOf(context);
    final speedOptions = <double>[0.5, 1.0, 1.5, 2.0];

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-screen video preview
          Positioned.fill(
            child: _applyPreviewFilter(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (ready)
                    FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: _controller!.value.size.width,
                        height: _controller!.value.size.height,
                        child: VideoPlayer(_controller!),
                      ),
                    ),
                  if (_showPosterOverlay)
                    _posterPath != null
                        ? Image.file(File(_posterPath!), fit: BoxFit.cover)
                        : Container(color: Colors.black),
                  if (!ready && _posterPath == null)
                    const Center(
                      child: CircularProgressIndicator(color: Colors.white38),
                    ),
                ],
              ),
            ),
          ),

          // Top gradient
          Positioned(
            top: 0, left: 0, right: 0,
            child: IgnorePointer(
              child: Container(
                height: pad.top + 70,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
              ),
            ),
          ),

          // Bottom gradient
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: IgnorePointer(
              child: Container(
                height: 320,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black, Colors.black87, Colors.transparent],
                  ),
                ),
              ),
            ),
          ),

          // Top bar
          Positioned(
            top: pad.top + 8,
            left: 16, right: 16,
            child: Row(
              children: [
                _GlassBtn(
                  icon: Icons.close_rounded,
                  onTap: () => Navigator.pop(context),
                ),
                const Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24, width: 0.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.all_inclusive, color: Colors.white, size: 16),
                      SizedBox(width: 6.w),
                      const Text(
                        'BOOMERANG',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 40),
              ],
            ),
          ),

          // Bottom controls overlay
          Positioned(
            left: 0, right: 0,
            bottom: pad.bottom + 12 + MediaQuery.viewInsetsOf(context).bottom,
            child: SingleChildScrollView(
              reverse: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Filter strip
                  SizedBox(
                    height: 40,
                    child: RotatedBox(
                      quarterTurns: -1,
                      child: ListWheelScrollView.useDelegate(
                        controller: _filterScrollCtrl,
                        itemExtent: 90,
                        perspective: 0.003,
                        diameterRatio: 6,
                        physics: const FixedExtentScrollPhysics(),
                        onSelectedItemChanged: (i) {
                          setState(() => _filterIdx = i);
                          HapticFeedback.selectionClick();
                        },
                        childDelegate: ListWheelChildBuilderDelegate(
                          childCount: _editorFilters.length,
                          builder: (context, i) {
                            final selected = i == _filterIdx;
                            return RotatedBox(
                              quarterTurns: 1,
                              child: Center(
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 200),
                                  style: TextStyle(
                                    color: selected ? Colors.white : Colors.white38,
                                    fontSize: selected ? 15 : 13,
                                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                                    letterSpacing: selected ? 0.5 : 0,
                                  ),
                                  child: Text(_editorFilters[i].label),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 12.h),

                  // Speed selector
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 48.w),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        children: speedOptions.map((s) {
                          final sel = (_speed - s).abs() < 0.01;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _speed = s;
                                  _controller?.setPlaybackSpeed(_speed);
                                });
                                HapticFeedback.selectionClick();
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                                padding: EdgeInsets.symmetric(vertical: 8.h),
                                decoration: BoxDecoration(
                                  color: sel ? Colors.white : Colors.transparent,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Center(
                                  child: Text(
                                    '${s}x',
                                    style: TextStyle(
                                      color: sel ? Colors.black : Colors.white60,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  SizedBox(height: 16.h),

                  // Clip length slider
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24.w),
                    child: Row(
                      children: [
                        const Icon(Icons.timelapse_rounded, color: Colors.white54, size: 18),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.white,
                              overlayColor: Colors.white12,
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 7,
                              ),
                            ),
                            child: Slider(
                              value: _segmentSeconds.clamp(0.8, 3.0),
                              min: 0.8,
                              max: 3.0,
                              divisions: 11,
                              onChanged: (v) => setState(() => _segmentSeconds = v),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: Text(
                            '${_segmentSeconds.toStringAsFixed(1)}s',
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16.h),

                  // Caption
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24.w),
                    child: TextField(
                      controller: _caption,
                      maxLines: 1,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      cursorColor: Colors.white,
                      decoration: InputDecoration(
                        hintText: 'Add a caption... #hashtags',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.08),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16.w,
                          vertical: 14.h,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        prefixIcon: Padding(
                          padding: EdgeInsets.only(left: 12.w, right: 4.w),
                          child: const Icon(
                            Icons.edit_rounded,
                            color: Colors.white30,
                            size: 18,
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(minWidth: 0),
                      ),
                    ),
                  ),
                  SizedBox(height: 20.h),

                  // Publish button
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24.w),
                    child: SizedBox(
                      width: double.infinity,
                      height: 54.h,
                      child: AnimatedBuilder(
                        animation: _publishAnim,
                        builder: (_, __) {
                          return ElevatedButton(
                            onPressed: _processing ? null : _onCreate,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              disabledBackgroundColor: Colors.white24,
                              disabledForegroundColor: Colors.white60,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _processing
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor: AlwaysStoppedAnimation(
                                            Colors.white.withValues(alpha: 0.8),
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 12.w),
                                      const Text(
                                        'Creating...',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.rocket_launch_rounded, size: 20),
                                      SizedBox(width: 8.w),
                                      const Text(
                                        'Publish',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Processing overlay
          if (_processing)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GlassBtn extends StatelessWidget {
  const _GlassBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 0.5),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
