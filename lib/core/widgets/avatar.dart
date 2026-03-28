import 'package:flutter/material.dart';

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.url,
    this.size = 40,
    this.iconSize,
  });

  final String? url;
  final double size;
  final double? iconSize;

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
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          url!,
          width: size,
          height: size,
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
  }
}
