import 'package:flutter/foundation.dart';

import 'package:boomerang/features/feed/domain/entities/ranked_post.dart';
import 'package:boomerang/features/feed/domain/ranking/feed_surface.dart';

/// Lightweight per-page diagnostic logging. For now this just hits
/// `debugPrint`; the call sites are designed to plug into a real analytics
/// sink later without churn at the controllers.
class FeedMetrics {
  const FeedMetrics();

  static const String rankingVersionV2 = 'v2';
  static const String rankingVersionLegacy = 'legacy';

  /// Emits a one-line diagnostic for the page that was just resolved.
  void recordPage({
    required FeedSurface surface,
    required List<RankedPost> page,
    required int pageIndex,
    required int sessionSeed,
    required String rankingVersion,
  }) {
    if (page.isEmpty) {
      debugPrint(
        '[feed] surface=$surface page=$pageIndex empty rv=$rankingVersion '
        'seed=$sessionSeed',
      );
      return;
    }
    final diversity = _diversityScore(page);
    final run = _longestAuthorRun(page);
    debugPrint(
      '[feed] surface=$surface page=$pageIndex size=${page.length} '
      'diversity=${diversity.toStringAsFixed(2)} '
      'maxAuthorRun=$run rv=$rankingVersion seed=$sessionSeed',
    );
  }

  /// Reports how much of [thisPage] is new compared to [previousPage].
  /// 1.0 = every item is new, 0.0 = identical page.
  void recordRefresh({
    required FeedSurface surface,
    required List<RankedPost> previousPage,
    required List<RankedPost> thisPage,
  }) {
    if (thisPage.isEmpty) return;
    final prevIds = previousPage.map((p) => p.id).toSet();
    final newCount = thisPage.where((p) => !prevIds.contains(p.id)).length;
    final novelty = newCount / thisPage.length;
    debugPrint(
      '[feed] surface=$surface refresh novelty=${novelty.toStringAsFixed(2)}',
    );
  }

  static double _diversityScore(List<RankedPost> page) {
    if (page.isEmpty) return 1.0;
    return 1.0 - (_longestAuthorRun(page) / page.length);
  }

  static int _longestAuthorRun(List<RankedPost> page) {
    if (page.isEmpty) return 0;
    var best = 1;
    var current = 1;
    for (var i = 1; i < page.length; i++) {
      if (page[i].authorId == page[i - 1].authorId) {
        current++;
        if (current > best) best = current;
      } else {
        current = 1;
      }
    }
    return best;
  }
}
