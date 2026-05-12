import 'package:boomerang/core/widgets/instagram_shimmer.dart';
import 'package:flutter/material.dart';

/// Poster cell for profile / discover / hashtag grids: IG shimmer until the image
/// decodes (or errors). Intended under a parent [ShimmerScope] (e.g. wrapping the
/// whole grid). If no scope is found, wraps itself in [ShimmerScope].
class BoomerangGridThumbnail extends StatefulWidget {
  const BoomerangGridThumbnail({
    super.key,
    this.imageUrl,
    required this.borderRadius,
    this.cacheWidth,
    this.phaseShift = 0,
    this.overlays = const [],
    /// When false, uses [ResizeImage] + [NetworkImage] like Discover.
    this.usePlainNetwork = true,
  });

  final String? imageUrl;
  final BorderRadius borderRadius;
  final int? cacheWidth;
  final double phaseShift;
  final List<Widget> overlays;
  final bool usePlainNetwork;

  @override
  State<BoomerangGridThumbnail> createState() => _BoomerangGridThumbnailState();
}

class _BoomerangGridThumbnailState extends State<BoomerangGridThumbnail> {
  bool _decoded = false;

  @override
  void didUpdateWidget(covariant BoomerangGridThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageUrl != oldWidget.imageUrl) {
      _decoded = false;
    }
  }

  void _markDecoded() {
    if (!_decoded && mounted) {
      setState(() => _decoded = true);
    }
  }

  Widget _shimmerLayer({required double shift}) {
    return Positioned.fill(
      child: AnimatedOpacity(
        opacity: _decoded ? 0 : 1,
        duration: const Duration(milliseconds: 220),
        child: ShimmerBone(
          width: double.infinity,
          height: double.infinity,
          borderRadius: BorderRadius.zero,
          phaseShift: shift % 1.0,
        ),
      ),
    );
  }

  Widget _imageStack(BuildContext context, double shift) {
    final url = widget.imageUrl;
    final hasUrl = url != null && url.isNotEmpty;

    if (!hasUrl) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ShimmerBone(
            width: double.infinity,
            height: double.infinity,
            borderRadius: BorderRadius.zero,
            phaseShift: shift % 1.0,
          ),
          ...widget.overlays,
        ],
      );
    }

    Widget builtImage;
    if (widget.usePlainNetwork) {
      builtImage = Image.network(
        url,
        fit: BoxFit.cover,
        cacheWidth: widget.cacheWidth,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSync) {
          final done = frame != null || wasSync;
          if (done) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _markDecoded());
          }
          return child;
        },
        errorBuilder: (_, __, ___) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _markDecoded());
          return ColoredBox(color: InstagramShimmerColors.lightBone);
        },
      );
    } else {
      final w = widget.cacheWidth ?? 1;
      builtImage = Image(
        image: ResizeImage.resizeIfNeeded(
          w,
          null,
          NetworkImage(url),
        ),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSync) {
          final done = frame != null || wasSync;
          if (done) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _markDecoded());
          }
          return child;
        },
        errorBuilder: (_, __, ___) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _markDecoded());
          return ColoredBox(color: InstagramShimmerColors.lightBone);
        },
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        builtImage,
        _shimmerLayer(shift: shift),
        ...widget.overlays,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final shift = widget.phaseShift;
    final core = ClipRRect(
      borderRadius: widget.borderRadius,
      child: _imageStack(context, shift),
    );

    if (ShimmerInherited.maybeOf(context) != null) {
      return core;
    }
    return ShimmerScope(child: core);
  }
}
