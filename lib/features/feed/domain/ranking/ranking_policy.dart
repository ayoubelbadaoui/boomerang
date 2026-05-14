import '../entities/ranked_post.dart';
import 'feed_surface.dart';
import 'ranking_weights.dart';
import 'score_components.dart';

/// Context passed into the policy for a single rerank pass. Everything
/// needed for personalization but nothing infrastructure-shaped.
class RankingContext {
  const RankingContext({
    required this.surface,
    required this.weights,
    required this.followingIds,
    required this.now,
    required this.sessionSeed,
    this.previouslyShown = const <RankedPost>[],
  });

  final FeedSurface surface;
  final RankingWeights weights;
  final Set<String> followingIds;
  final DateTime now;

  /// Same seed across pagination keeps the previously-shown ordering stable.
  final int sessionSeed;

  /// Tail of items already rendered on earlier pages this session. Used for
  /// cross-page author/topic burst control so the very first item of page 2
  /// doesn't repeat the last author of page 1.
  final List<RankedPost> previouslyShown;
}

/// Stateless ranking contract. Implementations live in the application
/// layer. Pure Dart — no IO, no side effects.
abstract class RankingPolicy {
  const RankingPolicy();

  /// Compute the per-component score for a single post in isolation.
  /// Diversity penalties are NOT included here — those are applied by
  /// [rerank] because they depend on neighbouring items.
  ScoreComponents score(RankedPost post, RankingContext context);

  /// Score + sort + apply diversity controls. Stable for a given
  /// (input order, sessionSeed) pair.
  List<RankedPost> rerank(
    List<RankedPost> candidates,
    RankingContext context,
  );
}
