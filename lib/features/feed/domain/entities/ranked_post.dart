/// Domain entity representing a single post in a ranked feed.
///
/// Pure Dart on purpose: no Flutter, no Firebase, no Riverpod imports.
/// Infrastructure is responsible for mapping Firestore document data into
/// this shape; presentation reads [raw] for fields the existing card UI
/// already understands.
class RankedPost {
  const RankedPost({
    required this.id,
    required this.authorId,
    required this.createdAt,
    required this.likes,
    required this.commentsCount,
    required this.hashtags,
    required this.ownerIsPrivate,
    required this.serverRankScore,
    required this.raw,
  });

  final String id;
  final String authorId;

  /// May be null for posts whose `createdAt` is still pending the server
  /// timestamp at insert time. Treat null as "now − 1 minute" when scoring.
  final DateTime? createdAt;

  final int likes;
  final int commentsCount;
  final List<String> hashtags;
  final bool ownerIsPrivate;

  /// `rankScore` written by the `recomputeRankScores` Cloud Function.
  /// Null when the function hasn't yet scored this doc, which is normal
  /// for brand-new posts. Clients tolerate null indefinitely.
  final double? serverRankScore;

  /// Pass-through of the underlying Firestore data map so the existing
  /// post card widgets keep reading the same fields (`videoUrl`, `caption`,
  /// `imageUrl`, `userName`, `userAvatar`, `likedBy`, …) without rewriting.
  final Map<String, dynamic> raw;

  String? get topHashtag => hashtags.isEmpty ? null : hashtags.first;
}
