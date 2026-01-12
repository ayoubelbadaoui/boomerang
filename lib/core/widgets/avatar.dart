import 'package:flutter/material.dart';

/// A simple avatar widget that falls back to a gray circle with an icon when no URL.
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
    if (hasUrl) {
      return CircleAvatar(
        radius: size / 2,
        backgroundImage: NetworkImage(url!),
        onBackgroundImageError: (_, __) {},
        backgroundColor: Colors.grey.shade200,
      );
    }
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: Colors.grey.shade300,
      child: Icon(
        Icons.person,
        color: Colors.grey.shade600,
        size: iconSize ?? size * 0.55,
      ),
    );
  }
}
