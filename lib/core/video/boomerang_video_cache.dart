import 'dart:async';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

/// Disk cache for boomerang videos.
///
/// `video_player` streams from the network with no persistent cache on either
/// platform, so without this every view — including scrolling back to a post
/// seen seconds ago — re-downloads the whole file. Boomerang files are
/// immutable (timestamped storage names), which makes them safe to cache
/// indefinitely; the LRU bounds below keep disk usage in check.
class BoomerangVideoCache {
  BoomerangVideoCache._();
  static final BoomerangVideoCache instance = BoomerangVideoCache._();

  static const _cacheKey = 'boomerangVideoCache';

  final CacheManager _cache = CacheManager(
    Config(
      _cacheKey,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 150,
    ),
  );

  final Set<String> _inFlight = <String>{};

  /// Returns a controller playing from the local cache when the video is
  /// already downloaded, else a network controller. A cache miss also kicks
  /// off a background download so the next view of the same video is instant.
  Future<VideoPlayerController> createController(String url) async {
    try {
      final cached = await _cache.getFileFromCache(url);
      if (cached != null && await cached.file.exists()) {
        return VideoPlayerController.file(cached.file);
      }
    } catch (_) {
      // Cache lookup failure must never block playback.
    }
    unawaited(warm(url));
    return VideoPlayerController.networkUrl(Uri.parse(url));
  }

  /// Downloads [url] into the cache if it isn't there yet. Deduped across
  /// concurrent callers; failures are swallowed (prefetch is best-effort).
  Future<void> warm(String url) async {
    if (url.isEmpty || _inFlight.contains(url)) return;
    _inFlight.add(url);
    try {
      final cached = await _cache.getFileFromCache(url);
      if (cached != null) return;
      await _cache.downloadFile(url);
    } catch (_) {
      // Best-effort.
    } finally {
      _inFlight.remove(url);
    }
  }

  /// Best-effort prefetch of the next few videos in a feed. Callers should
  /// keep [urls] short (1–3) — these are full-file downloads.
  void prefetch(Iterable<String> urls) {
    for (final url in urls) {
      unawaited(warm(url));
    }
  }
}
