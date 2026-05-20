import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:boomerang/features/feed/infrastructure/boomerang_processor.dart';
import 'package:boomerang/features/feed/infrastructure/gallery_video_ingestor.dart';
import 'package:boomerang/features/feed/presentation/editor/boomerang_editor_page.dart';
import 'package:boomerang/features/feed/presentation/editor/video_trim_page.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

// ---------------------------------------------------------------------------
// Filter definitions
// ---------------------------------------------------------------------------

class _CameraFilter {
  const _CameraFilter(this.label, this.icon, this.matrix, this.ffmpeg);
  final String label;
  final IconData icon;
  final ColorFilter? matrix;
  final String? ffmpeg;
}

const _filters = <_CameraFilter>[
  _CameraFilter('Original', Icons.auto_awesome, null, null),
  _CameraFilter(
    'Warm',
    Icons.wb_sunny_outlined,
    ColorFilter.matrix(<double>[
      1.2,
      0.1,
      0,
      0,
      15,
      0,
      1.08,
      0,
      0,
      8,
      0,
      0,
      0.9,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]),
    'colorbalance=rs=0.15:gs=0.05:bs=-0.15,eq=brightness=0.04',
  ),
  _CameraFilter(
    'Cool',
    Icons.ac_unit,
    ColorFilter.matrix(<double>[
      0.9,
      0,
      0.08,
      0,
      0,
      0,
      0.95,
      0.12,
      0,
      0,
      0,
      0.08,
      1.15,
      0,
      15,
      0,
      0,
      0,
      1,
      0,
    ]),
    'colorbalance=rs=-0.1:gs=0:bs=0.2,eq=brightness=0.02',
  ),
  _CameraFilter(
    'B&W',
    Icons.gradient,
    ColorFilter.matrix(<double>[
      0.33,
      0.33,
      0.33,
      0,
      0,
      0.33,
      0.33,
      0.33,
      0,
      0,
      0.33,
      0.33,
      0.33,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]),
    'hue=s=0',
  ),
  _CameraFilter(
    'Vivid',
    Icons.color_lens_outlined,
    ColorFilter.matrix(<double>[
      1.3,
      -0.1,
      0,
      0,
      8,
      0,
      1.3,
      -0.1,
      0,
      8,
      -0.1,
      0,
      1.3,
      0,
      8,
      0,
      0,
      0,
      1,
      0,
    ]),
    'eq=saturation=1.5:contrast=1.15:brightness=0.02',
  ),
];

// ---------------------------------------------------------------------------
// Main camera page
// ---------------------------------------------------------------------------

class BoomerangCameraPage extends StatefulWidget {
  const BoomerangCameraPage({super.key});

  @override
  State<BoomerangCameraPage> createState() => _BoomerangCameraPageState();
}

class _BoomerangCameraPageState extends State<BoomerangCameraPage>
    with TickerProviderStateMixin {
  static const _audioSession = MethodChannel('com.boomerang/audio_session');

  CameraController? _cam;
  List<CameraDescription> _cameras = [];
  int _camIdx = 0;
  bool _recording = false;
  bool _navigating = false;

  FlashMode _flash = FlashMode.off;
  double _zoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _baseZoom = 1.0;
  final Map<int, Offset> _pointers = {};
  final double _speed = 1.0;
  double _duration = 1.0;
  int _filterIdx = 0;
  Offset? _focusPoint;
  Timer? _burstTimer;

  late final AnimationController _progressAnim;
  late final AnimationController _flipAnim;
  late final AnimationController _focusAnim;

  late final AnimationController _pulseAnim;
  late final AnimationController _zoomBadgeAnim;

  @override
  void initState() {
    super.initState();
    _progressAnim = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (_duration * 1000).round()),
    );
    _flipAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _focusAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _zoomBadgeAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
    _initCameras();
  }

  Future<void> _initCameras() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;
    _camIdx = _cameras.indexWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
    );
    if (_camIdx < 0) _camIdx = 0;
    await _setupCam(_cameras[_camIdx]);
  }

  Future<void> _setupCam(CameraDescription desc) async {
    final prev = _cam;
    if (prev != null) await prev.dispose();
    final c = CameraController(desc, ResolutionPreset.high, enableAudio: false);
    _cam = c;
    try {
      await c.initialize();
      await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
      _minZoom = await c.getMinZoomLevel();
      _maxZoom = await c.getMaxZoomLevel();
      _zoom = _minZoom;
      if (desc.lensDirection == CameraLensDirection.back) {
        await c.setFlashMode(_flash);
      } else {
        await c.setFlashMode(FlashMode.off);
      }
      if (mounted) setState(() {});
      if (Platform.isIOS) await _restoreAudioSession();
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _restoreAudioSession() async {
    try {
      await _audioSession.invokeMethod('setAmbient');
    } catch (_) {}
  }

  Future<void> _deactivateAudioSession() async {
    try {
      await _audioSession.invokeMethod('deactivate');
    } catch (_) {}
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    _burstTimer?.cancel();
    _progressAnim.dispose();
    _flipAnim.dispose();
    _focusAnim.dispose();
    _pulseAnim.dispose();
    _zoomBadgeAnim.dispose();
    _cam?.dispose();
    if (Platform.isIOS) _deactivateAudioSession();
    super.dispose();
  }

  // -- Flash ---------------------------------------------------------------
  // Video recording uses FlashMode.torch (continuous light), not .always/.auto
  // which only fire for still captures. Front camera has no hardware flash —
  // we simulate it with a white screen overlay at max brightness.

  bool get _isFrontCamera =>
      _cameras.isNotEmpty &&
      _cameras[_camIdx].lensDirection == CameraLensDirection.front;

  void _cycleFlash() {
    const modes = [FlashMode.off, FlashMode.torch];
    final next = modes[(modes.indexOf(_flash) + 1) % modes.length];
    setState(() => _flash = next);
    if (!_isFrontCamera) {
      _cam?.setFlashMode(next);
    }
    HapticFeedback.lightImpact();
  }

  String get _flashLabel => _flash == FlashMode.torch ? 'On' : 'Off';

  IconData get _flashIcon =>
      _flash == FlashMode.torch
          ? Icons.flash_on_rounded
          : Icons.flash_off_rounded;

  // -- Flip ----------------------------------------------------------------

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || _recording) return;
    HapticFeedback.mediumImpact();
    _flipAnim.forward(from: 0);
    _camIdx = (_camIdx + 1) % _cameras.length;
    await _setupCam(_cameras[_camIdx]);
  }

  // -- Zoom + Focus (raw pointer tracking to bypass gesture arena) ---------

  double? _initialPinchDistance;

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2) {
      _initialPinchDistance = _distanceBetweenPointers();
      _baseZoom = _zoom;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    _pointers[e.pointer] = e.position;
    if (_pointers.length == 2 && _initialPinchDistance != null) {
      final currentDist = _distanceBetweenPointers();
      final scale = currentDist / _initialPinchDistance!;
      final z = (_baseZoom * scale).clamp(_minZoom, _maxZoom);
      if ((z - _zoom).abs() < 0.005) return;
      setState(() => _zoom = z);
      _cam?.setZoomLevel(z);
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _initialPinchDistance = null;
    // Single-finger tap → focus
    if (_pointers.isEmpty && _initialPinchDistance == null) {
      _setFocusAt(e.position);
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _initialPinchDistance = null;
  }

  double _distanceBetweenPointers() {
    final pts = _pointers.values.toList();
    return (pts[0] - pts[1]).distance;
  }

  void _setFocusAt(Offset globalPos) {
    final c = _cam;
    if (c == null || !c.value.isInitialized || _recording) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPos);
    final size = box.size;
    final x = (local.dx / size.width).clamp(0.0, 1.0);
    final y = (local.dy / size.height).clamp(0.0, 1.0);
    c.setFocusPoint(Offset(x, y));
    c.setExposurePoint(Offset(x, y));
    setState(() => _focusPoint = local);
    _focusAnim.forward(from: 0);
    HapticFeedback.selectionClick();
  }

  // -- Recording -----------------------------------------------------------

  void _onHoldStart() {
    if (_recording || _cam == null || _navigating) return;
    HapticFeedback.heavyImpact();
    _startRecording();
  }

  Future<void> _startRecording() async {
    final c = _cam;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.startVideoRecording();
      setState(() => _recording = true);
      _progressAnim.duration = Duration(
        milliseconds: (_duration * 1000).round(),
      );
      _progressAnim.forward(from: 0);
      _pulseAnim.repeat(reverse: true);
      _burstTimer = Timer(
        Duration(milliseconds: (_duration * 1000).round()),
        () {
          if (_recording) _stopRecording();
        },
      );
    } catch (e) {
      debugPrint('Record start error: $e');
    }
  }

  void _onHoldEnd() {
    if (!_recording) return;
    _stopRecording();
  }

  Future<void> _stopRecording() async {
    if (!_recording || _cam == null || _navigating) return;
    _burstTimer?.cancel();
    _progressAnim.stop();
    _progressAnim.reset();
    _pulseAnim.stop();
    _pulseAnim.reset();
    setState(() => _recording = false);
    HapticFeedback.mediumImpact();
    try {
      final xfile = await _cam!.stopVideoRecording();
      if (Platform.isIOS) await _restoreAudioSession();
      _navigating = true;
      if (!mounted) return;
      final selectedFilter = _filters[_filterIdx];
      final isFront =
          _cameras[_camIdx].lensDirection == CameraLensDirection.front;
      // Selfie mirroring is platform-dependent:
      //  - iOS (camera_avfoundation) saves the front-camera file already
      //    mirrored, matching the live preview. Applying our own hflip on
      //    top would double-flip it into a non-mirrored clip — which is
      //    exactly the "selfie looks flipped after recording" bug users hit.
      //  - Android's camera2 writes the raw (un-mirrored) sensor orientation
      //    to disk, so we *do* need to hflip ourselves to match the preview.
      // We only request mirroring for the Android case.
      final needsManualMirror = isFront && Platform.isAndroid;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder:
              (_) => BoomerangEditorPage(
                inputFile: File(xfile.path),
                initialSpeed: _speed,
                videoFilter: selectedFilter.ffmpeg,
                previewFilter: selectedFilter.matrix,
                mirrorVideo: needsManualMirror,
              ),
        ),
      );
      _navigating = false;
    } catch (e) {
      _navigating = false;
      debugPrint('Record stop error: $e');
    }
  }

  // -- Gallery import ------------------------------------------------------

  Future<void> _showGallerySheet() async {
    if (_recording || _navigating) return;
    HapticFeedback.mediumImpact();

    final picked = await showModalBottomSheet<_GalleryPickResult>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _GalleryImportSheet(),
    );

    if (picked == null || !mounted) return;

    _navigating = true;
    if (picked.needsTrim) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoTrimPage(inputFile: picked.file),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BoomerangEditorPage(inputFile: picked.file),
        ),
      );
    }
    _navigating = false;
  }

  // -- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = _cam;
    final ready = c != null && c.value.isInitialized;
    final pad = MediaQuery.paddingOf(context);
    final screenH = MediaQuery.sizeOf(context).height;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview (no gesture detector here — platform views absorb touches)
          if (ready)
            Positioned.fill(child: _filteredPreview(c))
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white38),
            ),

          // Raw pointer layer — bypasses gesture arena entirely for reliable
          // pinch-to-zoom on top of native platform views.
          if (ready)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                child: const SizedBox.expand(),
              ),
            ),

          // Front camera "screen flash" — bright white overlay while recording
          if (_recording && _flash == FlashMode.torch && _isFrontCamera)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: 0.7,
                  duration: const Duration(milliseconds: 150),
                  child: Container(color: Colors.white),
                ),
              ),
            ),

          // Top gradient for readability
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: pad.top + 80,
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
            bottom: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: screenH * 0.35,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
              ),
            ),
          ),

          // Focus ring
          if (_focusPoint != null)
            Positioned(
              left: _focusPoint!.dx - 32,
              top: _focusPoint!.dy - 32,
              child: AnimatedBuilder(
                animation: _focusAnim,
                builder: (_, __) {
                  final scale = 1.0 + 0.3 * (1.0 - _focusAnim.value);
                  final opacity = (1.0 - _focusAnim.value).clamp(0.0, 1.0);
                  return Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 1.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          // Zoom badge
          if (_zoom > _minZoom + 0.1)
            Positioned(
              top: pad.top + 70,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: AnimatedOpacity(
                    opacity: 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_zoom.toStringAsFixed(1)}x',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Top bar
          Positioned(
            top: pad.top + 12,
            left: 20,
            right: 20,
            child: AnimatedOpacity(
              opacity: _recording ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Row(
                children: [
                  _GlassButton(
                    icon: _flashIcon,
                    label: _flashLabel,
                    onTap: _cycleFlash,
                  ),
                  const Spacer(),
                  _GlassButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),

          // BOOMERANG label while recording
          if (_recording)
            Positioned(
              top: pad.top + 18,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedBuilder(
                  animation: _pulseAnim,
                  builder:
                      (_, __) => Opacity(
                        opacity: 0.6 + 0.4 * _pulseAnim.value,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.fiber_manual_record,
                                color: Colors.white,
                                size: 10,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'BOOMERANG',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                ),
              ),
            ),

          // Bottom controls
          Positioned(
            left: 0,
            right: 0,
            bottom: pad.bottom + 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Duration slider
                AnimatedOpacity(
                  opacity: _recording ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.timer_outlined,
                            color: Colors.white60,
                            size: 18,
                          ),
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
                                value: _duration,
                                min: 0.3,
                                max: 1.5,
                                divisions: 12,
                                onChanged: (v) => setState(() => _duration = v),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 38,
                            child: Text(
                              '${_duration.toStringAsFixed(1)}s',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Instagram-style swipeable filter names
                AnimatedOpacity(
                  opacity: _recording ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: _SnapFilterStrip(
                    filters: _filters,
                    selectedIndex: _filterIdx,
                    onChanged: (i) => setState(() => _filterIdx = i),
                  ),
                ),
                const SizedBox(height: 24),

                // Record row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _flipAnim,
                        builder:
                            (_, child) => Transform(
                              alignment: Alignment.center,
                              transform:
                                  Matrix4.identity()
                                    ..setEntry(3, 2, 0.001)
                                    ..rotateY(math.pi * _flipAnim.value),
                              child: child,
                            ),
                        child: _GlassButton(
                          icon: Icons.flip_camera_ios_rounded,
                          size: 52,
                          onTap: _flipCamera,
                        ),
                      ),
                      _RecordButton(
                        progress: _progressAnim,
                        pulse: _pulseAnim,
                        recording: _recording,
                        onStart: _onHoldStart,
                        onEnd: _onHoldEnd,
                      ),
                      _GlassButton(
                        icon: Icons.photo_library_rounded,
                        size: 52,
                        onTap: _showGallerySheet,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedOpacity(
                  opacity: _recording ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: const Text(
                    'Hold to record',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filteredPreview(CameraController c) {
    final f = _filters[_filterIdx].matrix;
    final preview = SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: c.value.previewSize?.height ?? 1,
          height: c.value.previewSize?.width ?? 1,
          child: CameraPreview(c),
        ),
      ),
    );
    if (f == null) return preview;
    return ColorFiltered(colorFilter: f, child: preview);
  }
}

// ---------------------------------------------------------------------------
// Glass-style button (backdrop blur look via translucent bg)
// ---------------------------------------------------------------------------

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.onTap,
    this.label,
    this.size = 42,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24, width: 0.5),
            ),
            child: Icon(icon, color: Colors.white, size: size * 0.5),
          ),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(
              label!,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Instagram-style snapping filter strip
// ---------------------------------------------------------------------------

class _SnapFilterStrip extends StatefulWidget {
  const _SnapFilterStrip({
    required this.filters,
    required this.selectedIndex,
    required this.onChanged,
  });
  final List<_CameraFilter> filters;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  State<_SnapFilterStrip> createState() => _SnapFilterStripState();
}

class _SnapFilterStripState extends State<_SnapFilterStrip> {
  late final FixedExtentScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = FixedExtentScrollController(
      initialItem: widget.selectedIndex,
    );
  }

  @override
  void didUpdateWidget(_SnapFilterStrip old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex) {
      _scrollController.animateToItem(
        widget.selectedIndex,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: RotatedBox(
        quarterTurns: -1,
        child: ListWheelScrollView.useDelegate(
          controller: _scrollController,
          itemExtent: 90,
          perspective: 0.003,
          diameterRatio: 6,
          physics: const FixedExtentScrollPhysics(),
          onSelectedItemChanged: (i) {
            widget.onChanged(i);
            HapticFeedback.selectionClick();
          },
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: widget.filters.length,
            builder: (context, i) {
              final selected = i == widget.selectedIndex;
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
                    child: Text(widget.filters[i].label),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Record button — Instagram-style: outer ring scales up on press,
// inner circle shrinks to rounded square, gradient progress ring.
// ---------------------------------------------------------------------------

class _RecordButton extends StatefulWidget {
  const _RecordButton({
    required this.progress,
    required this.pulse,
    required this.recording,
    required this.onStart,
    required this.onEnd,
  });
  final AnimationController progress;
  final AnimationController pulse;
  final bool recording;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  @override
  State<_RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<_RecordButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleAnim;

  static const _idleSize = 84.0;
  static const _pressedSize = 110.0;
  static const _innerIdle = 64.0;
  static const _innerRec = 34.0;

  @override
  void initState() {
    super.initState();
    _scaleAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void didUpdateWidget(_RecordButton old) {
    super.didUpdateWidget(old);
    if (widget.recording && !old.recording) {
      _scaleAnim.forward();
    } else if (!widget.recording && old.recording) {
      _scaleAnim.reverse();
    }
  }

  @override
  void dispose() {
    _scaleAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => widget.onStart(),
      onPointerUp: (_) => widget.onEnd(),
      onPointerCancel: (_) => widget.onEnd(),
      child: AnimatedBuilder(
        animation: Listenable.merge([
          widget.progress,
          widget.pulse,
          _scaleAnim,
        ]),
        builder: (_, __) {
          final t = Curves.easeOutBack.transform(_scaleAnim.value);
          final outerSize = _idleSize + (_pressedSize - _idleSize) * t;
          final pulseScale =
              widget.recording ? 1.0 + 0.02 * widget.pulse.value : 1.0;

          return SizedBox(
            width: _pressedSize,
            height: _pressedSize,
            child: Center(
              child: Transform.scale(
                scale: pulseScale,
                child: SizedBox(
                  width: outerSize,
                  height: outerSize,
                  child: CustomPaint(
                    painter: _RingPainter(
                      progress: widget.progress.value,
                      recording: widget.recording,
                      thickness: 4 + 2 * t,
                    ),
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        width: widget.recording ? _innerRec : _innerIdle,
                        height: widget.recording ? _innerRec : _innerIdle,
                        decoration: BoxDecoration(
                          color:
                              widget.recording
                                  ? Colors.redAccent
                                  : Colors.white,
                          borderRadius: BorderRadius.circular(
                            widget.recording ? 10 : _innerIdle / 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.recording,
    this.thickness = 4,
  });
  final double progress;
  final bool recording;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - thickness / 2 - 1;

    final bgPaint =
        Paint()
          ..color = recording ? Colors.white24 : Colors.white38
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness;
    canvas.drawCircle(center, radius, bgPaint);

    if (recording && progress > 0) {
      final arcPaint =
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = thickness + 1
            ..strokeCap = StrokeCap.round
            ..shader = SweepGradient(
              startAngle: -math.pi / 2,
              endAngle: 3 * math.pi / 2,
              colors: const [
                Colors.redAccent,
                Colors.orangeAccent,
                Colors.redAccent,
              ],
            ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        arcPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.recording != recording ||
      old.thickness != thickness;
}

// ---------------------------------------------------------------------------
// Bottom-sheet for gallery import (max 1.5 s)
// ---------------------------------------------------------------------------

class _GalleryImportSheet extends StatefulWidget {
  const _GalleryImportSheet();

  @override
  State<_GalleryImportSheet> createState() => _GalleryImportSheetState();
}

class _GalleryImportSheetState extends State<_GalleryImportSheet> {
  bool _picking = false;
  final _ingestor = GalleryVideoIngestor();

  // The user-selectable window budget. Anything longer goes through the
  // trim page; anything shorter is hard-trimmed from t=0 and sent straight
  // to the editor.
  static const _maxWindow = Duration(milliseconds: 1500);

  Future<void> _pickVideo() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picker = ImagePicker();
      // No maxDuration — we let the trim page handle long videos.
      final xfile = await picker.pickVideo(source: ImageSource.gallery);
      if (xfile == null) {
        if (mounted) Navigator.pop(context);
        return;
      }

      final ingested = await _ingestor.ingest(xfile);
      if (!mounted) return;

      final sourceDuration = ingested.duration;
      if (sourceDuration <= _maxWindow) {
        // Short clip → pre-trim to 1.5s from the start and hand straight to
        // the editor so the user doesn't sit through a pointless trim step.
        final trimmed = await const BoomerangProcessor().trimToMaxDuration(
          ingested.file.path,
          maxSeconds: 1.5,
        );
        if (!mounted) return;
        Navigator.pop(
          context,
          _GalleryPickResult(File(trimmed), needsTrim: false),
        );
      } else {
        Navigator.pop(
          context,
          _GalleryPickResult(ingested.file, needsTrim: true),
        );
      }
    } on GalleryVideoIngestException catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not import video: $e')));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Container(
      padding: EdgeInsets.fromLTRB(24, 20, 24, pad.bottom + 20),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Import from Gallery',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pick any video — you can trim the moment you want next.',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _picking ? null : _pickVideo,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                disabledBackgroundColor: Colors.white38,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon:
                  _picking
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black54,
                        ),
                      )
                      : const Icon(Icons.video_library_rounded),
              label: Text(_picking ? 'Opening…' : 'Choose Video'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white54,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom-sheet return payload. [needsTrim] tells the caller whether to
/// route the file through [VideoTrimPage] or straight to the editor.
class _GalleryPickResult {
  const _GalleryPickResult(this.file, {required this.needsTrim});
  final File file;
  final bool needsTrim;
}
