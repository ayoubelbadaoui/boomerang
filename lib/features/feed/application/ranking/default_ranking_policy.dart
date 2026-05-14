import 'dart:math' as math;

import 'package:boomerang/features/feed/domain/entities/ranked_post.dart';
import 'package:boomerang/features/feed/domain/ranking/ranking_policy.dart';
import 'package:boomerang/features/feed/domain/ranking/score_components.dart';

/// Default scoring + diversification implementation.
///
/// Pure Dart. No external state, no IO. Determinism is keyed on
/// `(post.id, context.sessionSeed)` so pagination doesn't reshuffle
/// previously rendered pages.
class DefaultRankingPolicy extends RankingPolicy {
  const DefaultRankingPolicy();

  static const double _likesSaturation = 6.0; // log1p(~400) ≈ 6
  static const double _commentsSaturation = 6.0;

  @override
  ScoreComponents score(RankedPost post, RankingContext context) {
    final w = context.weights;

    final ageHours = post.createdAt == null
        ? 1.0 / 60.0 // pending serverTimestamp ⇒ treat as "right now"
        : math.max(
            0.0,
            context.now.difference(post.createdAt!).inMinutes / 60.0,
          );
    final recency = math.exp(-ageHours / w.halfLifeHours);

    final relationship = context.followingIds.contains(post.authorId) ? 1.0 : 0.0;

    final likesPart = math.log(1 + post.likes) / _likesSaturation;
    final commentsPart = math.log(1 + post.commentsCount) / _commentsSaturation;
    final engagement =
        _clamp01(0.6 * likesPart + 0.4 * commentsPart);

    final serverScore = post.serverRankScore == null
        ? 0.0
        : _clamp01(post.serverRankScore!);

    final explorationRand = _deterministicJitter(post.id, context.sessionSeed);
    final exploration = explorationRand; // already in [0,1)

    final finalScore = w.recency * recency +
        w.relationship * relationship +
        w.engagement * engagement +
        w.serverScore * serverScore +
        w.exploration * exploration;

    return ScoreComponents(
      recency: recency,
      relationship: relationship,
      engagement: engagement,
      serverScore: serverScore,
      exploration: exploration,
      finalScore: finalScore,
    );
  }

  @override
  List<RankedPost> rerank(
    List<RankedPost> candidates,
    RankingContext context,
  ) {
    if (candidates.isEmpty) return const <RankedPost>[];

    // 1. Compute raw scores in a single pass.
    final scored = <_ScoredPost>[];
    for (final p in candidates) {
      final c = score(p, context);
      scored.add(_ScoredPost(post: p, score: c.finalScore));
    }

    // 2. Sort by score desc; ties broken by `createdAt` desc, then by id
    // ascending so the order is fully deterministic.
    scored.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      final aTs = a.post.createdAt?.millisecondsSinceEpoch ?? 0;
      final bTs = b.post.createdAt?.millisecondsSinceEpoch ?? 0;
      final tsCmp = bTs.compareTo(aTs);
      if (tsCmp != 0) return tsCmp;
      return a.post.id.compareTo(b.post.id);
    });

    // 3. Apply author/topic burst control by walking the sorted list and
    //    swapping forward when a burst is detected. Bounded window so this
    //    stays O(n * window).
    final ranked = scored.map((s) => s.post).toList(growable: true);
    final w = context.weights;
    if (w.authorBurstWindow > 0 || w.topicBurstWindow > 0) {
      _applyBurstControl(ranked, context);
    }
    return List<RankedPost>.unmodifiable(ranked);
  }

  // ── helpers ──────────────────────────────────────────────────────────

  static double _clamp01(double v) => v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);

  /// Stable per-(postId, sessionSeed) jitter in [0, 1). Same seed ⇒ same
  /// value, so pagination keeps page-1 stable when page-2 is appended.
  static double _deterministicJitter(String postId, int sessionSeed) {
    final seed = sessionSeed ^ postId.hashCode;
    return math.Random(seed).nextDouble();
  }

  /// Mutates [ranked] in place. For each slot, if it bursts against the
  /// previous-window neighbours OR the cross-page tail in
  /// [context.previouslyShown], pull forward the next eligible item from
  /// up to [_swapWindow] slots ahead. If none found, leave as-is.
  static const int _swapWindow = 5;

  static void _applyBurstControl(
    List<RankedPost> ranked,
    RankingContext context,
  ) {
    final tail = context.previouslyShown;
    final w = context.weights;

    bool burstsAt(int i, RankedPost candidate) {
      // Author burst against the prior items on this page.
      if (w.authorBurstWindow > 0) {
        final from = math.max(0, i - w.authorBurstWindow);
        for (var k = from; k < i; k++) {
          if (ranked[k].authorId == candidate.authorId) return true;
        }
        // Author burst against the tail of the previous page (first slot only).
        if (i == 0 && tail.isNotEmpty) {
          final tailFrom =
              math.max(0, tail.length - w.authorBurstWindow);
          for (var k = tailFrom; k < tail.length; k++) {
            if (tail[k].authorId == candidate.authorId) return true;
          }
        }
      }
      // Topic burst.
      if (w.topicBurstWindow > 0 && candidate.topHashtag != null) {
        final from = math.max(0, i - w.topicBurstWindow);
        var hits = 0;
        for (var k = from; k < i; k++) {
          if (ranked[k].topHashtag == candidate.topHashtag) hits++;
        }
        if (hits >= 2) return true;
      }
      return false;
    }

    for (var i = 0; i < ranked.length; i++) {
      if (!burstsAt(i, ranked[i])) continue;
      // Find the next non-bursting candidate within the swap window.
      final upper = math.min(ranked.length, i + 1 + _swapWindow);
      for (var j = i + 1; j < upper; j++) {
        if (!burstsAt(i, ranked[j])) {
          final tmp = ranked[i];
          ranked[i] = ranked[j];
          ranked[j] = tmp;
          break;
        }
      }
    }
  }
}

class _ScoredPost {
  _ScoredPost({required this.post, required this.score});
  final RankedPost post;
  final double score;
}
