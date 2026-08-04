import 'package:boomerang/core/widgets/boomerang_cached_image.dart';
import 'package:flutter/widgets.dart';

/// Precaches a list of network images with limited concurrency to avoid
/// overwhelming the HTTP connection pool (which causes "Connection closed
/// before full header was received" on Firebase Storage).
Future<void> precacheImages(
  List<String> urls,
  BuildContext context, {
  int concurrency = 4,
  int? cacheWidth,
}) async {
  final queue = List<String>.from(urls);
  final workers = <Future<void>>[];

  Future<void> worker() async {
    while (queue.isNotEmpty) {
      final url = queue.removeAt(0);
      try {
        await precacheImage(
          cachedNetworkImageProvider(url, cacheWidth: cacheWidth),
          context,
        );
      } catch (_) {
        // Individual failure is fine — skip and continue.
      }
    }
  }

  for (var i = 0; i < concurrency; i++) {
    workers.add(worker());
  }
  await Future.wait(workers);
}
