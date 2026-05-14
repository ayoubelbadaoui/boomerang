import '../entities/ranked_post.dart';
import '../ranking/feed_page.dart';

/// Pool of unranked candidates returned by the infrastructure layer. The
/// application layer (RankingPolicy + FeedController) is responsible for
/// turning this into a [FeedPage].
class CandidatePool {
  const CandidatePool({
    required this.posts,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<RankedPost> posts;
  final FeedCursor? nextCursor;
  final bool hasMore;

  static const empty = CandidatePool(
    posts: <RankedPost>[],
    nextCursor: null,
    hasMore: false,
  );
}

/// Surface-specific cursor for the Home pipeline. Encodes the tail of the
/// two candidate streams (followed + exploration). Both fields are
/// nullable because the page may have exhausted one stream but not the
/// other.
class HomeCursor extends FeedCursor {
  const HomeCursor({
    this.lastFollowingCreatedAtMs,
    this.lastExplorationScore,
    this.lastExplorationCreatedAtMs,
  });

  final int? lastFollowingCreatedAtMs;
  final double? lastExplorationScore;
  final int? lastExplorationCreatedAtMs;
}

/// Surface-specific cursor for Discovery. Either by `rankScore` (preferred)
/// or by `createdAt` (fallback when most docs lack a score).
class DiscoveryCursor extends FeedCursor {
  const DiscoveryCursor({
    this.lastRankScore,
    this.lastCreatedAtMs,
    this.fallbackChronological = false,
  });

  final double? lastRankScore;
  final int? lastCreatedAtMs;

  /// True when this cursor was issued during a chronological fallback. The
  /// repo uses this to keep paging on the same ordering.
  final bool fallbackChronological;
}

/// Abstract data-source for the ranked feed pipeline.
///
/// Only candidate fetching + privacy/block filtering lives here. Scoring
/// and diversity are in the application layer so the repo stays infra-only
/// and easy to swap (Firestore today, REST tomorrow).
abstract class FeedRepo {
  /// Candidates for the Home feed: posts by followed authors + a small
  /// exploration tail. Already filtered for privacy and blocks.
  Future<CandidatePool> fetchHomeCandidates({
    required String myUid,
    required Set<String> followingIds,
    required Set<String> blockedIds,
    HomeCursor? cursor,
    int followingLimit = 60,
    int explorationLimit = 20,
  });

  /// Candidates for Discovery: public posts ordered by server `rankScore`
  /// (preferred) or `createdAt` (fallback). Already filtered for blocks.
  /// Private posts never appear here.
  Future<CandidatePool> fetchDiscoveryCandidates({
    required String myUid,
    required Set<String> blockedIds,
    DiscoveryCursor? cursor,
    int limit = 80,
  });
}
