import '../entities/ranked_post.dart';

/// Opaque pagination token. Concrete shapes are surface-specific subclasses
/// in `feed_repo.dart`; presentation/application never opens this up.
abstract class FeedCursor {
  const FeedCursor();
}

/// A single page of ranked posts ready to be rendered.
class FeedPage {
  const FeedPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<RankedPost> items;
  final FeedCursor? nextCursor;
  final bool hasMore;

  static const empty =
      FeedPage(items: <RankedPost>[], nextCursor: null, hasMore: false);
}
