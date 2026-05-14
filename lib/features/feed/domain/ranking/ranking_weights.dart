import 'feed_surface.dart';

/// Tunable scalar weights for the ranking policy. Lives in domain so the
/// policy contract stays pure Dart. Mirrored (loosely) by
/// `functions/src/config/rankingWeights.ts` for the server-side
/// `rankScore` computation.
class RankingWeights {
  const RankingWeights({
    required this.recency,
    required this.relationship,
    required this.engagement,
    required this.serverScore,
    required this.exploration,
    required this.halfLifeHours,
    required this.authorBurstWindow,
    required this.topicBurstWindow,
  });

  /// How much exponential-decay freshness contributes.
  final double recency;

  /// How much "I follow this author" contributes.
  final double relationship;

  /// How much locally-computed engagement (likes + commentsCount) contributes.
  final double engagement;

  /// How much the server-computed `rankScore` contributes (0 when missing).
  final double serverScore;

  /// Magnitude of the bounded shuffle jitter.
  final double exploration;

  /// Half-life of the recency decay, in hours.
  final double halfLifeHours;

  /// "Don't show the same author in the previous N slots."
  final int authorBurstWindow;

  /// "Don't show the same top hashtag in the previous N slots."
  final int topicBurstWindow;

  static const home = RankingWeights(
    recency: 0.40,
    relationship: 0.35,
    engagement: 0.15,
    serverScore: 0.05,
    exploration: 0.05,
    halfLifeHours: 24,
    authorBurstWindow: 2,
    topicBurstWindow: 3,
  );

  static const discovery = RankingWeights(
    recency: 0.20,
    relationship: 0.05,
    engagement: 0.30,
    serverScore: 0.35,
    exploration: 0.10,
    halfLifeHours: 72,
    authorBurstWindow: 3,
    topicBurstWindow: 3,
  );

  /// Identity weights used when the legacy/disabled flag is on.
  /// Final score === recency only ⇒ exact chronological order.
  static const legacy = RankingWeights(
    recency: 1.0,
    relationship: 0.0,
    engagement: 0.0,
    serverScore: 0.0,
    exploration: 0.0,
    halfLifeHours: 1e9, // effectively no decay
    authorBurstWindow: 0,
    topicBurstWindow: 0,
  );

  static RankingWeights forSurface(FeedSurface surface) {
    switch (surface) {
      case FeedSurface.home:
        return home;
      case FeedSurface.discovery:
        return discovery;
    }
  }
}
