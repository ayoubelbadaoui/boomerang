import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Fullscreen viewer for profile pictures with Hero animation,
/// pinch-to-zoom, and drag-to-dismiss.
class FullscreenAvatarViewer extends StatefulWidget {
  const FullscreenAvatarViewer({
    super.key,
    required this.imageUrl,
    required this.heroTag,
  });

  final String imageUrl;
  final String heroTag;

  static void open(
    BuildContext context, {
    required String imageUrl,
    required String heroTag,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, animation, __) => FullscreenAvatarViewer(
          imageUrl: imageUrl,
          heroTag: heroTag,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  State<FullscreenAvatarViewer> createState() => _FullscreenAvatarViewerState();
}

class _FullscreenAvatarViewerState extends State<FullscreenAvatarViewer>
    with TickerProviderStateMixin {
  final _transformationController = TransformationController();

  Offset _dragOffset = Offset.zero;
  bool _isDragging = false;

  late final AnimationController _snapBackController;
  late Animation<Offset> _snapBackAnimation;

  static const _dismissThreshold = 100.0;
  static const _velocityThreshold = 800.0;

  bool get _isZoomed =>
      _transformationController.value.getMaxScaleOnAxis() > 1.05;

  double get _dragProgress =>
      (_dragOffset.dy.abs() / (MediaQuery.of(context).size.height * 0.4))
          .clamp(0.0, 1.0);

  double get _backgroundOpacity => 1.0 - _dragProgress * 0.8;

  double get _imageScale => 1.0 - _dragProgress * 0.25;

  @override
  void initState() {
    super.initState();
    _snapBackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _snapBackAnimation =
        Tween<Offset>(begin: Offset.zero, end: Offset.zero).animate(
      CurvedAnimation(parent: _snapBackController, curve: Curves.easeOutCubic),
    );
    _snapBackController.addListener(() {
      setState(() => _dragOffset = _snapBackAnimation.value);
    });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _snapBackController.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    if (_isZoomed) return;
    _snapBackController.stop();
    setState(() => _isDragging = true);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_isZoomed) return;
    setState(() => _dragOffset += details.delta);
  }

  void _onPanEnd(DragEndDetails details) {
    if (_isZoomed) return;
    setState(() => _isDragging = false);

    final velocity = details.velocity.pixelsPerSecond.dy.abs();
    final distance = _dragOffset.dy.abs();

    if (distance > _dismissThreshold || velocity > _velocityThreshold) {
      Navigator.of(context).pop();
    } else {
      _snapBackAnimation =
          Tween<Offset>(begin: _dragOffset, end: Offset.zero).animate(
        CurvedAnimation(
            parent: _snapBackController, curve: Curves.easeOutCubic),
      );
      _snapBackController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    final animating = _isDragging || _snapBackController.isAnimating;
    final scale = animating ? _imageScale : 1.0;
    final bgOpacity = animating ? _backgroundOpacity : 1.0;
    final cornerRadius = _isDragging ? 16.0 * _dragProgress * 2 : 0.0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedContainer(
              duration:
                  _isDragging ? Duration.zero : const Duration(milliseconds: 200),
              color: Colors.black.withValues(alpha: bgOpacity),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: Center(
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..translate(_dragOffset.dx, _dragOffset.dy)
                    ..scale(scale),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(math.min(cornerRadius, 20)),
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      panEnabled: _isZoomed,
                      scaleEnabled: true,
                      minScale: 1,
                      maxScale: 5,
                      child: Hero(
                        tag: widget.heroTag,
                        child: Image.network(
                          widget.imageUrl,
                          fit: BoxFit.contain,
                          loadingBuilder: (_, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white54,
                              size: 48,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: padding.top + 8,
              right: 16,
              child: AnimatedOpacity(
                opacity: _isDragging ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black45,
                  ),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
