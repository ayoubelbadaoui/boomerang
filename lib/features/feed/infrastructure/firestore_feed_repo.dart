import 'dart:developer' as developer;

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
    developer.log(
      '[FEEDDBG] fetchHomeCandidates uid=$myUid following=${followingIds.length} '
      'blocked=${blockedIds.length} followingExhausted=$followingExhausted '
      'fallbackChrono=${cursor?.fallbackChronological ?? false}',
      name: 'FirestoreFeedRepo',
    );

    // Stage 1 — followed feed first. This keeps Home feeling personal for
    // users who already follow people.
    if (!followingExhausted) {
      developer.log('[FEEDDBG] home stage=FOLLOWING', name: 'FirestoreFeedRepo');
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
    developer.log('[FEEDDBG] home stage=EXPLORATION', name: 'FirestoreFeedRepo');
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
      if (cursor == null) {
        // First page: fetch score-ranked and chronological orderings in
        // parallel and MERGE them — scored (hot, recent) posts first, then
        // the rest by recency. Only a tiny slice of posts ever carries a
        // `rankScore` (the scheduler scores a rolling 7-day window), so the
        // score query alone would surface only those few and hide everything
        // else. Merging guarantees the full public catalogue is reachable.
        final results = await Future.wait([
          _boomerangs.fetchPublicByRankScorePage(limit: limit),
          _boomerangs.fetchPublicByCreatedAtPage(limit: limit),
        ]);
        return _packDiscoveryFirstPage(
          scoreDocs: results[0].docs,
          timeDocs: results[1].docs,
          myUid: myUid,
          blockedIds: blockedIds,
          requested: limit,
        );
      }
      final snap = await _boomerangs.fetchPublicByRankScorePage(
        startAfterScore: cursor.lastRankScore,
        limit: limit,
      );
      return _packDiscoveryByScore(
        docs: snap.docs,
        myUid: myUid,
        blockedIds: blockedIds,
        requested: limit,
      );
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

  /// Merges the first score-ranked page with the first chronological page:
  /// scored posts (in score order) come first, then chronological posts with
  /// duplicates dropped. Continuation is always chronological — the feed
  /// controller dedups by id, so scored posts re-seen in the time stream are
  /// harmless.
  CandidatePool _packDiscoveryFirstPage({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> scoreDocs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> timeDocs,
    required String myUid,
    required Set<String> blockedIds,
    required int requested,
  }) {
    final byId = <String, RankedPost>{};
    final ordered = <RankedPost>[];

    void take(QueryDocumentSnapshot<Map<String, dynamic>> d) {
      if (byId.containsKey(d.id)) return;
      final data = d.data();
      if (!_passesFilters(
        data: data,
        myUid: myUid,
        blockedIds: blockedIds,
        followingIds: const <String>{},
      )) {
        return;
      }
      final post = _mapDoc(d.id, data);
      byId[d.id] = post;
      ordered.add(post);
    }

    for (final d in scoreDocs) {
      take(d);
    }
    int? lastMs;
    for (final d in timeDocs) {
      take(d);
      final t = BoomerangRepo.createdAtMillis(d.data()['createdAt']);
      if (t != null) lastMs = t;
    }

    // The chronological page bounds pagination: if it filled, there is more
    // to page through chronologically; otherwise the whole catalogue fit.
    final hasMore = timeDocs.length >= requested;
    return CandidatePool(
      posts: ordered,
      hasMore: hasMore,
      nextCursor: hasMore
          ? DiscoveryCursor(
              lastRankScore: null,
              lastCreatedAtMs: lastMs,
              fallbackChronological: true,
            )
          : null,
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
      final t = BoomerangRepo.createdAtMillis(data['createdAt']);
      if (t != null) lastMs = t;
    }
    // A full page means more scored posts may remain; a partial page means the
    // scored set is drained, so transition to a chronological pass (from the
    // newest post) to surface the far larger pool of unscored posts instead of
    // ending the feed. Either way there is always more to show.
    final scoredFull = docs.length >= requested;
    return CandidatePool(
      posts: posts,
      hasMore: true,
      nextCursor: scoredFull
          ? DiscoveryCursor(
              lastRankScore: lastScore,
              lastCreatedAtMs: lastMs,
              fallbackChronological: false,
            )
          : const DiscoveryCursor(
              lastRankScore: null,
              lastCreatedAtMs: null,
              fallbackChronological: true,
            ),
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
      final t = BoomerangRepo.createdAtMillis(data['createdAt']);
      if (t != null) lastMs = t;
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
      final t = BoomerangRepo.createdAtMillis(data['createdAt']);
      if (t != null) {
        lastFollowingMs = t;
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
      if (cursor?.lastExplorationScore == null) {
        // First exploration page: MERGE score-ranked and chronological pages
        // (mirrors fetchDiscoveryCandidates) so the vast majority of posts —
        // which never carry a rankScore — remain reachable instead of being
        // hidden behind the score-only ordering.
        final results = await Future.wait([
          _boomerangs.fetchPublicByRankScorePage(limit: limit),
          _boomerangs.fetchPublicByCreatedAtPage(
            startAfterMillis: cursor?.lastExplorationCreatedAtMs,
            limit: limit,
          ),
        ]);
        return _packHomeExplorationFirstPage(
          scoreDocs: results[0].docs,
          timeDocs: results[1].docs,
          myUid: myUid,
          followingIds: followingIds,
          blockedIds: blockedIds,
          requested: limit,
          previous: cursor,
        );
      }
      final snap = await _boomerangs.fetchPublicByRankScorePage(
        startAfterScore: cursor!.lastExplorationScore,
        limit: limit,
      );
      return _packHomeExplorationByScore(
        docs: snap.docs,
        myUid: myUid,
        followingIds: followingIds,
        blockedIds: blockedIds,
        requested: limit,
        previous: cursor,
      );
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
      final authorId = _asString(data['userId']);
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
      final t = BoomerangRepo.createdAtMillis(data['createdAt']);
      if (t != null) lastMs = t;
    }
    // Partial page ⇒ scored set drained ⇒ transition to chronological so
    // unscored posts still surface (mirrors _packDiscoveryByScore).
    final scoredFull = docs.length >= requested;
    return CandidatePool(
      posts: posts,
      hasMore: true,
      nextCursor: scoredFull
          ? HomeCursor(
              lastFollowingCreatedAtMs: previous?.lastFollowingCreatedAtMs,
              lastExplorationScore: lastScore,
              lastExplorationCreatedAtMs: lastMs,
              followingExhausted: true,
              fallbackChronological: false,
            )
          : HomeCursor(
              lastFollowingCreatedAtMs: previous?.lastFollowingCreatedAtMs,
              lastExplorationScore: null,
              lastExplorationCreatedAtMs: null,
              followingExhausted: true,
              fallbackChronological: true,
            ),
    );
  }

  /// Home-exploration analogue of [_packDiscoveryFirstPage]: scored posts
  /// first, then chronological, both excluding followed authors and self.
  CandidatePool _packHomeExplorationFirstPage({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> scoreDocs,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> timeDocs,
    required String myUid,
    required Set<String> followingIds,
    required Set<String> blockedIds,
    required int requested,
    required HomeCursor? previous,
  }) {
    final byId = <String, RankedPost>{};
    final ordered = <RankedPost>[];

    void take(QueryDocumentSnapshot<Map<String, dynamic>> d) {
      if (byId.containsKey(d.id)) return;
      final data = d.data();
      final authorId = _asString(data['userId']);
      if (followingIds.contains(authorId) || authorId == myUid) return;
      if (!_passesFilters(
        data: data,
        myUid: myUid,
        blockedIds: blockedIds,
        followingIds: followingIds,
      )) {
        return;
      }
      final post = _mapDoc(d.id, data);
      byId[d.id] = post;
      ordered.add(post);
    }

    for (final d in scoreDocs) {
      take(d);
    }
    int? lastMs;
    for (final d in timeDocs) {
      take(d);
      final t = BoomerangRepo.createdAtMillis(d.data()['createdAt']);
      if (t != null) lastMs = t;
    }

    final hasMore = timeDocs.length >= requested;
    return CandidatePool(
      posts: ordered,
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
      final authorId = _asString(data['userId']);
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
      final t = BoomerangRepo.createdAtMillis(data['createdAt']);
      if (t != null) lastMs = t;
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
    final authorId = _asString(data['userId']);
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
    final createdMs = BoomerangRepo.createdAtMillis(data['createdAt']);
    final createdAt = createdMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(createdMs);

    final tagsRaw = data['hashtags'];
    final hashtags = tagsRaw is List
        ? tagsRaw.whereType<String>().toList(growable: false)
        : const <String>[];

    final rawScore = data['rankScore'];
    final serverRankScore = rawScore is num ? rawScore.toDouble() : null;

    return RankedPost(
      id: id,
      authorId: _asString(data['userId']),
      createdAt: createdAt,
      likes: _asInt(data['likes']),
      commentsCount: _asInt(data['commentsCount']),
      hashtags: hashtags,
      ownerIsPrivate: data['ownerIsPrivate'] == true,
      serverRankScore: serverRankScore,
      raw: data,
    );
  }

  /// Defensive coercion for legacy/imported documents whose fields may not
  /// match the current schema (e.g. counters stored as strings). Never
  /// throws — a single malformed field must not fail the whole feed page.
  static String _asString(Object? value) => value is String ? value : '';

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
