import 'dart:ui';

import 'package:boomerang/core/widgets/boomerang_grid_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Fullscreen boomerang renderer that keeps framing stable between poster and
/// video while avoiding destructive crop for heavily mismatched aspect ratios.
class FullscreenBoomerangMedia extends StatelessWidget {
  const FullscreenBoomerangMedia({
    super.key,
    required this.controller,
    required this.posterUrl,
    required this.showPosterOverlay,
    this.explicitVideoAspectRatio,
  });

  final VideoPlayerController? controller;
  final String? posterUrl;
  final bool showPosterOverlay;
  final double? explicitVideoAspectRatio;

  static const double _coverThreshold = 0.12;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final screenAspect =
        size.height > 0 ? (size.width / size.height) : (9.0 / 16.0);
    final hasPoster = posterUrl != null && posterUrl!.isNotEmpty;
    final hasVideo = controller != null && controller!.value.isInitialized;

    final mediaAspect = _resolveMediaAspect(screenAspect);
    final fit = _resolveFit(screenAspect: screenAspect, mediaAspect: mediaAspect);

    return Stack(
      fit: StackFit.expand,
      children: [
        _BackgroundFill(
          fit: BoxFit.cover,
          posterUrl: posterUrl,
          controller: controller,
          cacheWidth: _cacheWidth(context, maxPx: 2600),
        ),
        // Dim/blur layer so letterboxing on contain feels intentional.
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.black.withValues(alpha: 0.32)),
          ),
        ),
        if (hasVideo)
          _ForegroundVideo(
            controller: controller!,
            fit: fit,
            key: const ValueKey('video'),
          )
        else if (hasPoster)
          _ForegroundPoster(
            url: posterUrl!,
            fit: fit,
            cacheWidth: _cacheWidth(context, maxPx: 2800),
            key: const ValueKey('poster-fallback'),
          )
        else
          const ColoredBox(color: Colors.black),
        if (hasPoster && showPosterOverlay)
          _ForegroundPoster(
            url: posterUrl!,
            fit: fit,
            cacheWidth: _cacheWidth(context, maxPx: 2800),
            key: const ValueKey('poster-overlay'),
          ),
      ],
    );
  }

  double _resolveMediaAspect(double fallback) {
    final fromMetadata = explicitVideoAspectRatio;
    if (fromMetadata != null && fromMetadata.isFinite && fromMetadata > 0) {
      return fromMetadata;
    }
    final c = controller;
    if (c != null && c.value.isInitialized) {
      final ar = c.value.aspectRatio;
      if (ar.isFinite && ar > 0) return ar;
    }
    return fallback;
  }

  BoxFit _resolveFit({
    required double screenAspect,
    required double mediaAspect,
  }) {
    final delta = ((mediaAspect - screenAspect).abs() / screenAspect).abs();
    return delta <= _coverThreshold ? BoxFit.cover : BoxFit.contain;
  }

  int _cacheWidth(BuildContext context, {required int maxPx}) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final logical = size.width > size.height ? size.width : size.height;
    return computeCacheWidthForLogicalWidth(
      logical,
      dpr,
      maxPx: maxPx,
      scale: 1.05,
    );
  }
}

class _BackgroundFill extends StatelessWidget {
  const _BackgroundFill({
    required this.fit,
    required this.posterUrl,
    required this.controller,
    required this.cacheWidth,
  });

  final BoxFit fit;
  final String? posterUrl;
  final VideoPlayerController? controller;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    final hasPoster = posterUrl != null && posterUrl!.isNotEmpty;
    final hasVideo = controller != null && controller!.value.isInitialized;

    if (hasPoster) {
      return Image.network(
        posterUrl!,
        fit: fit,
        cacheWidth: cacheWidth,
        errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black),
      );
    }
    if (hasVideo) {
      return FittedBox(
        fit: fit,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: controller!.value.size.width,
          height: controller!.value.size.height,
          child: VideoPlayer(controller!),
        ),
      );
    }
    return const ColoredBox(color: Colors.black);
  }
}

class _ForegroundVideo extends StatelessWidget {
  const _ForegroundVideo({super.key, required this.controller, required this.fit});

  final VideoPlayerController controller;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: fit,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

class _ForegroundPoster extends StatelessWidget {
  const _ForegroundPoster({
    super.key,
    required this.url,
    required this.fit,
    required this.cacheWidth,
  });

  final String url;
  final BoxFit fit;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: fit,
      cacheWidth: cacheWidth,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}
