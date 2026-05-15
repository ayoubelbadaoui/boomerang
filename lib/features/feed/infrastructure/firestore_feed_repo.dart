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
    final hasFollowing = followingIds.isNotEmpty;
    final followingExhausted = cursor?.followingExhausted ?? !hasFollowing;

    // Stage 1 — followed feed first. This keeps Home feeling personal for
    // users who already follow people.
    if (!followingExhausted) {
      final followingDocs = await _boomerangs.fetchFollowingByCreatedAtPage(
        followingIds: followingIds,
        myUid: myUid,
        startAfterMillis: cursor?.lastFollowingCreatedAtMs,
        limit: followingLimit,
      );
      final packed = _packHomeFollowing(
        docs: followingDocs,
        myUid: myUid,
        followingIds: followingIds,
        blockedIds: blockedIds,
        requested: followingLimit,
      );
      // Keep paging follows while there are more.
      if (packed.hasMore) {
        return packed;
      }
      // If follows are exhausted but we still surfaced some posts, hand
      // them to the user first and flip to exploration on next page.
      if (packed.posts.isNotEmpty) {
        return CandidatePool(
          posts: packed.posts,
          hasMore: true,
          nextCursor: HomeCursor(
            lastFollowingCreatedAtMs:
                (packed.nextCursor as HomeCursor?)?.lastFollowingCreatedAtMs ??
                    cursor?.lastFollowingCreatedAtMs,
            lastExplorationScore: cursor?.lastExplorationScore,
            lastExplorationCreatedAtMs: cursor?.lastExplorationCreatedAtMs,
            followingExhausted: true,
            fallbackChronological: cursor?.fallbackChronological ?? false,
          ),
        );
      }
      // No visible followed posts left; immediately switch to exploration.
    }

    // Stage 2 — ranked exploration for fresh users or once follows dry up.
    return _fetchHomeExploration(
      myUid: myUid,
      followingIds: followingIds,
      blockedIds: blockedIds,
      cursor: cursor,
      limit: explorationLimit,
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

  CandidatePool _packHomeFollowing({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required String myUid,
    required Set<String> followingIds,
    required Set<String> blockedIds,
    required int requested,
  }) {
    final posts = <RankedPost>[];
    int? lastFollowingMs;
    for (final d in docs) {
      final data = d.data();
      if (!_passesFilters(
        data: data,
        myUid: myUid,
        blockedIds: blockedIds,
        followingIds: followingIds,
      )) {
        continue;
      }
      posts.add(_mapDoc(d.id, data));
      final t = data['createdAt'];
      if (t is Timestamp) {
        lastFollowingMs = t.millisecondsSinceEpoch;
      }
    }
    final hasMore = docs.length >= requested;
    return CandidatePool(
      posts: posts,
      hasMore: hasMore,
      nextCursor: HomeCursor(
        lastFollowingCreatedAtMs: lastFollowingMs,
        followingExhausted: !hasMore,
      ),
    );
  }

  Future<CandidatePool> _fetchHomeExploration({
    required String myUid,
    required Set<String> followingIds,
    required Set<String> blockedIds,
    required HomeCursor? cursor,
    required int limit,
  }) async {
    final useChronologicalFallback = cursor?.fallbackChronological ?? false;
    if (!useChronologicalFallback) {
      final snap = await _boomerangs.fetchPublicByRankScorePage(
        startAfterScore: cursor?.lastExplorationScore,
        limit: limit,
      );
      if (snap.docs.isNotEmpty) {
        return _packHomeExplorationByScore(
          docs: snap.docs,
          myUid: myUid,
          followingIds: followingIds,
          blockedIds: blockedIds,
          requested: limit,
          previous: cursor,
        );
      }
      // No rankScore yet (or exhausted right away): chronological fallback.
      if (cursor == null || cursor.lastExplorationScore == null) {
        final fallback = await _boomerangs.fetchPublicByCreatedAtPage(
          startAfterMillis: cursor?.lastExplorationCreatedAtMs,
          limit: limit,
        );
        return _packHomeExplorationByTime(
          docs: fallback.docs,
          myUid: myUid,
          followingIds: followingIds,
          blockedIds: blockedIds,
          requested: limit,
          previous: cursor,
        );
      }
      return CandidatePool.empty;
    }
    final snap = await _boomerangs.fetchPublicByCreatedAtPage(
      startAfterMillis: cursor?.lastExplorationCreatedAtMs,
      limit: limit,
    );
    return _packHomeExplorationByTime(
      docs: snap.docs,
      myUid: myUid,
      followingIds: followingIds,
      blockedIds: blockedIds,
      requested: limit,
      previous: cursor,
    );
  }

  CandidatePool _packHomeExplorationByScore({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required String myUid,
    required Set<String> followingIds,
    required Set<String> blockedIds,
    required int requested,
    required HomeCursor? previous,
  }) {
    final posts = <RankedPost>[];
    double? lastScore;
    int? lastMs;
    for (final d in docs) {
      final data = d.data();
      final authorId = (data['userId'] ?? '') as String;
      // Exploration on Home should prefer non-followed authors.
      if (followingIds.contains(authorId) || authorId == myUid) continue;
      if (!_passesFilters(
        data: data,
        myUid: myUid,
        blockedIds: blockedIds,
        followingIds: followingIds,
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
      hasMore: hasMore,
      nextCursor: hasMore
          ? HomeCursor(
              lastFollowingCreatedAtMs: previous?.lastFollowingCreatedAtMs,
              lastExplorationScore: lastScore,
              lastExplorationCreatedAtMs: lastMs,
              followingExhausted: true,
              fallbackChronological: false,
            )
          : null,
    );
  }

  CandidatePool _packHomeExplorationByTime({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    required String myUid,
    required Set<String> followingIds,
    required Set<String> blockedIds,
    required int requested,
    required HomeCursor? previous,
  }) {
    final posts = <RankedPost>[];
    int? lastMs;
    for (final d in docs) {
      final data = d.data();
      final authorId = (data['userId'] ?? '') as String;
      if (followingIds.contains(authorId) || authorId == myUid) continue;
      if (!_passesFilters(
        data: data,
        myUid: myUid,
        blockedIds: blockedIds,
        followingIds: followingIds,
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
      hasMore: hasMore,
      nextCursor: hasMore
          ? HomeCursor(
              lastFollowingCreatedAtMs: previous?.lastFollowingCreatedAtMs,
              lastExplorationScore: null,
              lastExplorationCreatedAtMs: lastMs,
              followingExhausted: true,
              fallbackChronological: true,
            )
          : null,
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
