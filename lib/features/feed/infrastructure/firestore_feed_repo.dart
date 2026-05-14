import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:boomerang/features/feed/domain/entities/ranked_post.dart';
import 'package:boomerang/features/feed/domain/repositories/feed_repo.dart';

import 'boomerang_repo.dart';

/// Firestore-backed implementation of [FeedRepo]. The only place in the
/// feed feature that depends on `cloud_firestore` types.
class FirestoreFeedRepo implements FeedRepo {
  FirestoreFeedRepo(this._boomerangs);

  final BoomerangRepo _boomerangs;

  // ── Home ─────────────────────────────────────────────────────────────

  @override
  Future<CandidatePool> fetchHomeCandidates({
    required String myUid,
    required Set<String> followingIds,
    required Set<String> blockedIds,
    HomeCursor? cursor,
    int followingLimit = 60,
    int explorationLimit = 20,
  }) async {
    // 1. Followed authors (createdAt-cursor pagination).
    final followingDocs = await _boomerangs.fetchFollowingByCreatedAtPage(
      followingIds: followingIds,
      myUid: myUid,
      startAfterMillis: cursor?.lastFollowingCreatedAtMs,
      limit: followingLimit,
    );

    // 2. Exploration: globally hi-score public posts whose author the user
    //    does not follow. Skipped when the dataset has no rankScore yet —
    //    in that case the follow set carries the page on its own.
    final explorationSnap = await _boomerangs.fetchPublicByRankScorePage(
      startAfterScore: cursor?.lastExplorationScore,
      limit: explorationLimit,
    );

    // 3. Combine + filter + map to domain.
    final seenIds = <String>{};
    final candidates = <RankedPost>[];

    int? lastFollowingMs;
    for (final d in followingDocs) {
      final data = d.data();
      if (!_passesFilters(
        data: data,
        myUid: myUid,
        blockedIds: blockedIds,
        followingIds: followingIds,
      )) {
        continue;
      }
      if (!seenIds.add(d.id)) continue;
      candidates.add(_mapDoc(d.id, data));
      final t = data['createdAt'];
      if (t is Timestamp) {
        lastFollowingMs = t.millisecondsSinceEpoch;
      }
    }

    double? lastExplorationScore;
    int? lastExplorationMs;
    for (final d in explorationSnap.docs) {
      final data = d.data();
      final authorId = (data['userId'] ?? '') as String;
      // Skip authors already represented by the follow set ⇒ exploration
      // genuinely brings new authors in.
      if (followingIds.contains(authorId) || authorId == myUid) continue;
      if (!_passesFilters(
        data: data,
        myUid: myUid,
        blockedIds: blockedIds,
        followingIds: followingIds,
      )) {
        continue;
      }
      if (!seenIds.add(d.id)) continue;
      candidates.add(_mapDoc(d.id, data));
      final s = data['rankScore'];
      if (s is num) lastExplorationScore = s.toDouble();
      final t = data['createdAt'];
      if (t is Timestamp) lastExplorationMs = t.millisecondsSinceEpoch;
    }

    final hasMore = followingDocs.length >= followingLimit ||
        explorationSnap.docs.length >= explorationLimit;
    final next = hasMore
        ? HomeCursor(
            lastFollowingCreatedAtMs: lastFollowingMs ??
                cursor?.lastFollowingCreatedAtMs,
            lastExplorationScore:
                lastExplorationScore ?? cursor?.lastExplorationScore,
            lastExplorationCreatedAtMs:
                lastExplorationMs ?? cursor?.lastExplorationCreatedAtMs,
          )
        : null;

    return CandidatePool(
      posts: candidates,
      nextCursor: next,
      hasMore: hasMore,
    );
  }

  // ── Discovery ────────────────────────────────────────────────────────

  @override
  Future<CandidatePool> fetchDiscoveryCandidates({
    required String myUid,
    required Set<String> blockedIds,
    DiscoveryCursor? cursor,
    int limit = 80,
  }) async {
    final useChronologicalFallback = cursor?.fallbackChronological ?? false;
    if (!useChronologicalFallback) {
      final snap = await _boomerangs.fetchPublicByRankScorePage(
        startAfterScore: cursor?.lastRankScore,
        limit: limit,
      );
      if (snap.docs.isNotEmpty) {
        return _packDiscoveryByScore(
          docs: snap.docs,
          myUid: myUid,
          blockedIds: blockedIds,
          requested: limit,
        );
      }
      // First call exhausted the score index entirely — fall back to time.
      if (cursor == null) {
        final fallback = await _boomerangs.fetchPublicByCreatedAtPage(
          startAfterMillis: null,
          limit: limit,
        );
        return _packDiscoveryByTime(
          docs: fallback.docs,
          myUid: myUid,
          blockedIds: blockedIds,
          requested: limit,
        );
      }
      // Mid-pagination ran out of scored docs.
      return CandidatePool.empty;
    }
    // Continue chronological pagination once we've already fallen back.
    final snap = await _boomerangs.fetchPublicByCreatedAtPage(
      startAfterMillis: cursor?.lastCreatedAtMs,
      limit: limit,
    );
    return _packDiscoveryByTime(
      docs: snap.docs,
      myUid: myUid,
      blockedIds: blockedIds,
      requested: limit,
    );
  }

  CandidatePool _packDiscoveryByScore({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required String myUid,
    required Set<String> blockedIds,
    required int requested,
  }) {
    final posts = <RankedPost>[];
    double? lastScore;
    int? lastMs;
    for (final d in docs) {
      final data = d.data();
      if (!_passesFilters(
        data: data,
        myUid: myUid,
        blockedIds: blockedIds,
        followingIds: const <String>{},
      )) {
        continue;
      }
      posts.add(_mapDoc(d.id, data));
      final s = data['rankScore'];
      if (s is num) lastScore = s.toDouble();
      final t = data['createdAt'];
      if (t is Timestamp) lastMs = t.millisecondsSinceEpoch;
    }
    final hasMore = docs.length >= requested;
    return CandidatePool(
      posts: posts,
      nextCursor: hasMore
          ? DiscoveryCursor(
              lastRankScore: lastScore,
              lastCreatedAtMs: lastMs,
              fallbackChronological: false,
            )
          : null,
      hasMore: hasMore,
    );
  }

  CandidatePool _packDiscoveryByTime({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required String myUid,
    required Set<String> blockedIds,
    required int requested,
  }) {
    final posts = <RankedPost>[];
    int? lastMs;
    for (final d in docs) {
      final data = d.data();
      if (!_passesFilters(
        data: data,
        myUid: myUid,
        blockedIds: blockedIds,
        followingIds: const <String>{},
      )) {
        continue;
      }
      posts.add(_mapDoc(d.id, data));
      final t = data['createdAt'];
      if (t is Timestamp) lastMs = t.millisecondsSinceEpoch;
    }
    final hasMore = docs.length >= requested;
    return CandidatePool(
      posts: posts,
      nextCursor: hasMore
          ? DiscoveryCursor(
              lastRankScore: null,
              lastCreatedAtMs: lastMs,
              fallbackChronological: true,
            )
          : null,
      hasMore: hasMore,
    );
  }

  // ── helpers ──────────────────────────────────────────────────────────

  bool _passesFilters({
    required Map<String, dynamic> data,
    required String myUid,
    required Set<String> blockedIds,
    required Set<String> followingIds,
  }) {
    final authorId = (data['userId'] ?? '') as String;
    if (authorId.isEmpty) return false;
    if (blockedIds.contains(authorId)) return false;
    // Privacy gate — defense-in-depth alongside firestore.rules.
    final ownerIsPrivate = data['ownerIsPrivate'] == true;
    if (ownerIsPrivate &&
        authorId != myUid &&
        !followingIds.contains(authorId)) {
      return false;
    }
    return true;
  }

  RankedPost _mapDoc(String id, Map<String, dynamic> data) {
    final ts = data['createdAt'];
    DateTime? createdAt;
    if (ts is Timestamp) createdAt = ts.toDate();

    final tagsRaw = data['hashtags'];
    final hashtags = tagsRaw is List
        ? tagsRaw.whereType<String>().toList(growable: false)
        : const <String>[];

    final rawScore = data['rankScore'];
    final serverRankScore = rawScore is num ? rawScore.toDouble() : null;

    return RankedPost(
      id: id,
      authorId: (data['userId'] ?? '') as String,
      createdAt: createdAt,
      likes: (data['likes'] is int)
          ? data['likes'] as int
          : ((data['likes'] ?? 0) as num).toInt(),
      commentsCount: (data['commentsCount'] is int)
          ? data['commentsCount'] as int
          : ((data['commentsCount'] ?? 0) as num).toInt(),
      hashtags: hashtags,
      ownerIsPrivate: data['ownerIsPrivate'] == true,
      serverRankScore: serverRankScore,
      raw: data,
    );
  }
}
