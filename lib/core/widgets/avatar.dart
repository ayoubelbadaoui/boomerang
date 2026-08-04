import 'package:boomerang/core/widgets/boomerang_cached_image.dart';
import 'package:boomerang/core/widgets/fullscreen_avatar_viewer.dart';
import 'package:flutter/material.dart';

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.url,
    this.size = 40,
    this.iconSize,
    this.enableFullscreen = false,
    this.heroTag,
  });

  final String? url;
  final double size;
  final double? iconSize;

  /// When true, tapping the avatar opens a fullscreen viewer with Hero animation.
  final bool enableFullscreen;

  /// Hero tag used for the shared-element transition.
  /// Auto-generated from [url] when null and [enableFullscreen] is true.
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final hasUrl = url != null && url!.trim().isNotEmpty;
    final placeholder = CircleAvatar(
      radius: size / 2,

      backgroundColor: Colors.grey.shade300,
      child: Icon(
        Icons.person,
        color: Colors.grey.shade600,
        size: iconSize ?? size * 0.55,
      ),
    );

    if (!hasUrl) return placeholder;

    final cacheSize = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final tag = heroTag ?? 'avatar_fullscreen_${url.hashCode}';

    Widget image = ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: BoomerangCachedImage(
          url: url!,
          fit: BoxFit.cover,
          cacheWidth: cacheSize,
          cacheHeight: cacheSize,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) return child;
            return placeholder;
          },
          errorBuilder: (_, __, ___) => placeholder,
        ),
      ),
    );

    if (enableFullscreen) {
      image = Hero(
        tag: tag,
        child: image,
      );
      image = GestureDetector(
        onTap: () => FullscreenAvatarViewer.open(
          context,
          imageUrl: url!,
          heroTag: tag,
        ),
        child: image,
      );
    }

    return image;
  }
}
