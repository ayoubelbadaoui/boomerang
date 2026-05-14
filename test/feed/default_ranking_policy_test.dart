import 'package:boomerang/features/feed/application/ranking/default_ranking_policy.dart';
import 'package:boomerang/features/feed/domain/entities/ranked_post.dart';
import 'package:boomerang/features/feed/domain/ranking/feed_surface.dart';
import 'package:boomerang/features/feed/domain/ranking/ranking_policy.dart';
import 'package:boomerang/features/feed/domain/ranking/ranking_weights.dart';
import 'package:flutter_test/flutter_test.dart';

RankedPost _post({
  required String id,
  required String authorId,
  required int hoursAgo,
  int likes = 0,
  int comments = 0,
  List<String> hashtags = const <String>[],
  bool ownerIsPrivate = false,
  double? serverRankScore,
}) {
  final now = DateTime(2026, 1, 1, 12);
  return RankedPost(
    id: id,
    authorId: authorId,
    createdAt: now.subtract(Duration(hours: hoursAgo)),
    likes: likes,
    commentsCount: comments,
    hashtags: hashtags,
    ownerIsPrivate: ownerIsPrivate,
    serverRankScore: serverRankScore,
    raw: const <String, dynamic>{},
  );
}

RankingContext _context({
  required FeedSurface surface,
  Set<String> following = const <String>{},
  int seed = 42,
  List<RankedPost> tail = const <RankedPost>[],
}) {
  return RankingContext(
    surface: surface,
    weights: RankingWeights.forSurface(surface),
    followingIds: following,
    now: DateTime(2026, 1, 1, 12),
    sessionSeed: seed,
    previouslyShown: tail,
  );
}

void main() {
  group('DefaultRankingPolicy.score', () {
    const policy = DefaultRankingPolicy();

    test('newer post outranks older when all other signals equal', () {
      final fresh = _post(id: 'a', authorId: 'u1', hoursAgo: 1);
      final stale = _post(id: 'b', authorId: 'u1', hoursAgo: 48);
      final ctx = _context(surface: FeedSurface.home);

      final freshScore = policy.score(fresh, ctx).finalScore;
      final staleScore = policy.score(stale, ctx).finalScore;
      expect(freshScore, greaterThan(staleScore));
    });

    test('Home: relationship dominates a fresh non-followed post', () {
      // Followed but slightly older
      final followed = _post(id: 'f', authorId: 'friend', hoursAgo: 6);
      // Brand-new, not followed, modest engagement
      final stranger = _post(
        id: 's',
        authorId: 'stranger',
        hoursAgo: 1,
        likes: 50,
      );
      final ctx =
          _context(surface: FeedSurface.home, following: const {'friend'});

      expect(
        policy.score(followed, ctx).finalScore,
        greaterThan(policy.score(stranger, ctx).finalScore),
      );
    });

    test(
        'Discovery: engagement + server score dominate over a non-followed '
        'brand-new post', () {
      final freshNoSignals = _post(id: 'a', authorId: 'u1', hoursAgo: 0);
      final engagedAndScored = _post(
        id: 'b',
        authorId: 'u2',
        hoursAgo: 24,
        likes: 500,
        comments: 100,
        serverRankScore: 0.9,
      );
      final ctx = _context(surface: FeedSurface.discovery);

      expect(
        policy.score(engagedAndScored, ctx).finalScore,
        greaterThan(policy.score(freshNoSignals, ctx).finalScore),
      );
    });
  });

  group('DefaultRankingPolicy.rerank', () {
    const policy = DefaultRankingPolicy();

    test('breaks long author runs when alternatives exist', () {
      // 5 by A, 3 by B, 3 by C — enough alternatives to interleave.
      final posts = <RankedPost>[
        for (var i = 0; i < 5; i++)
          _post(id: 'a$i', authorId: 'A', hoursAgo: i, likes: 100),
        for (var i = 0; i < 3; i++)
          _post(id: 'b$i', authorId: 'B', hoursAgo: i, likes: 100),
        for (var i = 0; i < 3; i++)
          _post(id: 'c$i', authorId: 'C', hoursAgo: i, likes: 100),
      ];
      final ranked = policy.rerank(
        posts,
        _context(surface: FeedSurface.home, following: const {'A', 'B', 'C'}),
      );

      var maxRun = 1;
      var current = 1;
      for (var i = 1; i < ranked.length; i++) {
        if (ranked[i].authorId == ranked[i - 1].authorId) {
          current++;
          if (current > maxRun) maxRun = current;
        } else {
          current = 1;
        }
      }
      // Burst control with a window of 2 prior slots aims to keep runs at
      // most 3. Without burst control the raw sort produces a 5-run for A,
      // so anything ≤ 3 demonstrates the policy is actively interleaving.
      expect(maxRun, lessThanOrEqualTo(3));
      // Also: the unranked baseline would surface all 5 A's contiguously.
      // Verify we actually broke that up.
      final aPositions = <int>[
        for (var i = 0; i < ranked.length; i++)
          if (ranked[i].authorId == 'A') i,
      ];
      expect(aPositions.length, equals(5));
      expect(
        aPositions.last - aPositions.first,
        greaterThan(4),
        reason: 'A-posts should be spread, not bunched at the top',
      );
    });

    test('is deterministic for a fixed sessionSeed', () {
      final posts = <RankedPost>[
        for (var i = 0; i < 12; i++)
          _post(
            id: 'p$i',
            authorId: 'u${i % 4}',
            hoursAgo: i,
            likes: 10 * i,
          ),
      ];
      final ctx = _context(surface: FeedSurface.discovery, seed: 7);
      final a = policy.rerank(posts, ctx).map((p) => p.id).toList();
      final b = policy.rerank(posts, ctx).map((p) => p.id).toList();
      expect(a, equals(b));
    });

    test('different sessionSeed produces a different ordering', () {
      final posts = <RankedPost>[
        for (var i = 0; i < 20; i++)
          _post(
            id: 'p$i',
            authorId: 'u${i % 4}',
            hoursAgo: i,
            likes: 10,
          ),
      ];
      final a = policy
          .rerank(posts, _context(surface: FeedSurface.discovery, seed: 1))
          .map((p) => p.id)
          .toList();
      final b = policy
          .rerank(posts, _context(surface: FeedSurface.discovery, seed: 999))
          .map((p) => p.id)
          .toList();
      // The set of items is the same; their order should differ.
      expect(a.toSet(), equals(b.toSet()));
      expect(a, isNot(equals(b)));
    });

    test('legacy weights ⇒ pure createdAt desc ordering', () {
      final posts = <RankedPost>[
        _post(id: 'old', authorId: 'A', hoursAgo: 100, likes: 99999),
        _post(id: 'mid', authorId: 'B', hoursAgo: 10),
        _post(id: 'new', authorId: 'C', hoursAgo: 1),
      ];
      final ctx = RankingContext(
        surface: FeedSurface.home,
        weights: RankingWeights.legacy,
        followingIds: const {},
        now: DateTime(2026, 1, 1, 12),
        sessionSeed: 0,
        previouslyShown: const <RankedPost>[],
      );
      final ranked = policy.rerank(posts, ctx).map((p) => p.id).toList();
      expect(ranked, equals(<String>['new', 'mid', 'old']));
    });
  });
}
