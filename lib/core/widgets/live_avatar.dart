import 'package:boomerang/core/widgets/avatar.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Avatar that resolves the current profile picture from Firestore in real time.
///
/// Uses [userProfileByIdProvider] so Riverpod deduplicates listeners: multiple
/// widgets showing the same user share a single Firestore snapshot stream.
/// While the live profile loads, [fallbackUrl] (typically the denormalized
/// snapshot stored on the document) is shown so there is no visual flicker.
class LiveAvatar extends ConsumerWidget {
  const LiveAvatar({
    super.key,
    required this.userId,
    this.fallbackUrl,
    this.size = 40,
    this.iconSize,
    this.enableFullscreen = false,
    this.heroTag,
  });

  final String userId;
  final String? fallbackUrl;
  final double size;
  final double? iconSize;

  /// When true, tapping the avatar opens a fullscreen viewer.
  final bool enableFullscreen;

  /// Hero tag for the shared-element transition.
  final String? heroTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (userId.isEmpty) {
      return AppAvatar(
        url: fallbackUrl,
        size: size,
        iconSize: iconSize,
        enableFullscreen: enableFullscreen,
        heroTag: heroTag,
      );
    }

    final profileAsync = ref.watch(userProfileByIdProvider(userId));
    final liveUrl = profileAsync.whenData((p) => p?.avatarUrl).value;
    final url = liveUrl ?? fallbackUrl;

    return AppAvatar(
      url: url,
      size: size,
      iconSize: iconSize,
      enableFullscreen: enableFullscreen,
      heroTag: heroTag,
    );
  }
}
