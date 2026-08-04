import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Disk- and memory-cached network image for feed posters and avatars.
/// Uses [CachedNetworkImage] so scrolled-past content reloads instantly.
class BoomerangCachedImage extends StatelessWidget {
  const BoomerangCachedImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.cacheHeight,
    this.frameBuilder,
    this.errorBuilder,
    this.placeholder,
  });

  final String url;
  final BoxFit fit;
  final int? cacheWidth;
  final int? cacheHeight;
  final ImageFrameBuilder? frameBuilder;
  final ImageErrorWidgetBuilder? errorBuilder;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      maxWidthDiskCache: cacheWidth,
      maxHeightDiskCache: cacheHeight,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (_, __) => placeholder ?? const SizedBox.shrink(),
      errorWidget:
          errorBuilder == null
              ? (_, __, ___) => const SizedBox.shrink()
              : (context, url, error) =>
                  errorBuilder!(context, error, StackTrace.current),
      imageBuilder:
          frameBuilder == null
              ? null
              : (context, imageProvider) {
                return Image(
                  image: imageProvider,
                  fit: fit,
                  frameBuilder: frameBuilder,
                );
              },
    );
  }
}

/// Builds a [CachedNetworkImageProvider] for [precacheImage].
ImageProvider<Object> cachedNetworkImageProvider(
  String url, {
  int? cacheWidth,
}) {
  ImageProvider<Object> provider = CachedNetworkImageProvider(url);
  if (cacheWidth != null) {
    provider = ResizeImage(provider, width: cacheWidth);
  }
  return provider;
}
