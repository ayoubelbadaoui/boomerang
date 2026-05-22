import 'dart:async';
import 'dart:developer' show log;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:boomerang/features/feed/domain/entities/ranked_post.dart';
import 'package:boomerang/features/feed/domain/ranking/feed_page.dart';
import 'package:boomerang/features/feed/domain/ranking/feed_surface.dart';
import 'package:boomerang/features/feed/domain/ranking/ranking_policy.dart';
import 'package:boomerang/features/feed/domain/ranking/ranking_weights.dart';
import 'package:boomerang/features/feed/domain/repositories/feed_repo.dart';
import 'package:boomerang/features/moderation/application/moderation_providers.dart';
import 'package:boomerang/infrastructure/providers.dart';

import 'feed_providers.dart';
import 'ranking/feed_metrics.dart';
import 'ranking/session_seed.dart';

/// Immutable per-surface controller state.
class FeedState {
  const FeedState({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
    required this.isLoading,
    required this.sessionSeed,
    required this.seenIds,
    required this.pageIndex,
    required this.rankingVersion,
    required this.rankingDirty,
    required this.pendingReorder,
  });

  final List<RankedPost> items;
  final FeedCursor? nextCursor;
  final bool hasMore;
  final bool isLoading;
  final int sessionSeed;
  final Set<String> seenIds;
  final int pageIndex;
  final String rankingVersion;
  final bool rankingDirty;
  final bool pendingReorder;

  FeedState copyWith({
    List<RankedPost>? items,
    FeedCursor? nextCursor,
    bool clearCursor = false,
    bool? hasMore,
    bool? isLoading,
    int? sessionSeed,
    Set<String>? seenIds,
    int? pageIndex,
    String? rankingVersion,
    bool? rankingDirty,
    bool? pendingReorder,
  }) {
    return FeedState(
      items: items ?? this.items,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      hasMore: hasMore ?? this.hasMore,
      isLoading: isLoading ?? this.isLoading,
      sessionSeed: sessionSeed ?? this.sessionSeed,
      seenIds: seenIds ?? this.seenIds,
      pageIndex: pageIndex ?? this.pageIndex,
      rankingVersion: rankingVersion ?? this.rankingVersion,
      rankingDirty: rankingDirty ?? this.rankingDirty,
      pendingReorder: pendingReorder ?? this.pendingReorder,
    );
  }

  static const empty = FeedState(
    items: <RankedPost>[],
    nextCursor: null,
    hasMore: true,
    isLoading: false,
    sessionSeed: 0,
    seenIds: <String>{},
    pageIndex: 0,
    rankingVersion: FeedMetrics.rankingVersionV2,
    rankingDirty: false,
    pendingReorder: false,
  );
}

/// One controller per [FeedSurface]. Maintains pagination, session seed,
/// dedup set, and ranking version. Presentation reads `state.value.items`
/// and calls `refresh()` / `fetchNext()`.
class FeedController extends FamilyAsyncNotifier<FeedState, FeedSurface> {
  static const int _pageSize = 20;
  static const FeedMetrics _metrics = FeedMetrics();
  static const Duration _rankReconcileDebounce = Duration(milliseconds: 1000);
  static const double _localLikeRankDelta = 0.015;
  static const int _refreshFreshnessWindowSize = 6;

  late FeedSurface _surface;
  Timer? _rankReconcileTimer;
  bool _rankReconcileInFlight = false;
  bool _bootFetchScheduled = false;

  @override
  Future<FeedState> build(FeedSurface arg) async {
    _surface = arg;
    ref.onDispose(() {
      _rankReconcileTimer?.cancel();
    });
    final authUid = ref.watch(
      authStateProvider.select((auth) => auth.asData?.value?.uid),
    );
    final seed = SessionSeed.bootstrap(
      uid: authUid ?? 'anon',
      surface: arg.name,
    );
    final initial = FeedState.empty.copyWith(
      sessionSeed: seed.value,
      seenIds: <String>{},
      pageIndex: 0,
      hasMore: true,
      clearCursor: true,
    );
    // Kick off first page after the initial AsyncData is committed.
    // Microtask can fire too early (state.value == null) and drop startup load.
    _scheduleInitialFetch();
    return initial;
  }

  void _scheduleInitialFetch() {
    if (_bootFetchScheduled) return;
    _bootFetchScheduled = true;
    Future<void>(() async {
      _bootFetchScheduled = false;
      await fetchNext();
    });
  }

  Future<void> refresh() async {
    final auth = ref.read(firebaseAuthProvider);
    final me = auth.currentUser ?? await ref.read(authStateProvider.future);
    final rotated =
        SessionSeed.bootstrap(
          uid: me?.uid ?? 'anon',
          surface: _surface.name,
          now: DateTime.now(),
        ).rotated();

    final previous = state.value?.items ?? const <RankedPost>[];

    state = AsyncData(
      FeedState.empty.copyWith(
        sessionSeed: rotated.value,
        seenIds: <String>{},
        pageIndex: 0,
        hasMore: true,
        clearCursor: true,
      ),
    );
    await fetchNext();
    _applyRefreshFreshnessPin();
    final next = state.value?.items ?? const <RankedPost>[];
    _metrics.recordRefresh(
      surface: _surface,
      previousPage: previous,
      thisPage: next,
    );
  }

  Future<void> fetchNext() async {
    final current = state.value;
    if (current == null) {
      _scheduleInitialFetch();
      return;
    }
    if (current.isLoading || !current.hasMore) return;

    state = AsyncData(current.copyWith(isLoading: true));

    try {
      final auth = ref.read(firebaseAuthProvider);
      final me = auth.currentUser ?? await ref.read(authStateProvider.future);
      if (me == null) {
        // Startup race: auth stream may not have emitted yet. Keep pagination
        // open so first load can succeed automatically once auth resolves.
        state = AsyncData(current.copyWith(isLoading: false));
        return;
      }
      final requestUid = me.uid;
      final followingIds = await _resolveFollowingIds(requestUid: requestUid);
      final blockedIds = await _resolveBlockedIds(requestUid: requestUid);
      final liveUidAfterDeps = ref.read(firebaseAuthProvider).currentUser?.uid;
      if (liveUidAfterDeps != requestUid) {
        state = AsyncData(current.copyWith(isLoading: false));
        return;
      }
      final policy = ref.read(rankingPolicyProvider);
      final flag = ref.read(rankingFeatureFlagProvider);

      final useLegacy = flag == RankingFlag.disabled;
      final weights =
          useLegacy
              ? RankingWeights.legacy
              : RankingWeights.forSurface(_surface);
      final rankingVersion =
          useLegacy
              ? FeedMetrics.rankingVersionLegacy
              : FeedMetrics.rankingVersionV2;

      final repo = ref.read(feedRepoProvider);
      final pool = await _fetchPool(
        repo: repo,
        cursor: current.nextCursor,
        myUid: me.uid,
        followingIds: followingIds,
        blockedIds: blockedIds,
      );

      // Filter out anything we've already shown this session.
      final fresh = pool.posts
          .where((p) => !current.seenIds.contains(p.id))
          .toList(growable: false);

      // Re-rank using the policy + previously-shown tail for cross-page
      // burst control.
      final tail =
          current.items.length > 5
              ? current.items.sublist(current.items.length - 5)
              : current.items;
      final context = RankingContext(
        surface: _surface,
        weights: weights,
        followingIds: followingIds,
        now: DateTime.now(),
        sessionSeed: current.sessionSeed,
        previouslyShown: tail,
      );
      final ranked = policy.rerank(fresh, context);
      final pageSlice = ranked.take(_pageSize).toList(growable: false);

      final mergedItems = <RankedPost>[...current.items, ...pageSlice];
      final mergedSeen = <String>{
        ...current.seenIds,
        ...pageSlice.map((p) => p.id),
      };

      final exhausted = !pool.hasMore && fresh.length <= pageSlice.length;

      _metrics.recordPage(
        surface: _surface,
        page: pageSlice,
        pageIndex: current.pageIndex,
        sessionSeed: current.sessionSeed,
        rankingVersion: rankingVersion,
      );

      final liveUid = ref.read(firebaseAuthProvider).currentUser?.uid;
      if (liveUid != requestUid) {
        // Keep UI interactive; a new account session is already in progress.
        state = AsyncData(current.copyWith(isLoading: false));
        return;
      }

      state = AsyncData(
        current.copyWith(
          items: mergedItems,
          nextCursor: pool.nextCursor,
          hasMore: !exhausted,
          isLoading: false,
          seenIds: mergedSeen,
          pageIndex: current.pageIndex + 1,
          rankingVersion: rankingVersion,
        ),
      );
    } catch (e, st) {
      log(
        'feed fetchNext failed',
        name: 'FeedController',
        error: e,
        stackTrace: st,
      );
      state = AsyncError(e, st);
    }
  }

  Future<Set<String>> _resolveFollowingIds({required String requestUid}) async {
    final cached = ref.read(followingIdsProvider).value;
    if (cached != null) return cached;
    try {
      final wait = ref.read(feedDependencyMaxWaitProvider);
      final resolved = await ref
          .read(followingIdsProvider.future)
          .timeout(wait);
      final liveUid = ref.read(firebaseAuthProvider).currentUser?.uid;
      if (liveUid != requestUid) return const <String>{};
      return resolved;
    } on TimeoutException {
      log(
        'followingIdsProvider timed out during feed fetch; using empty fallback',
        name: 'FeedController',
      );
      return const <String>{};
    } catch (e, st) {
      log(
        'followingIdsProvider unavailable during feed fetch; using empty fallback',
        name: 'FeedController',
        error: e,
        stackTrace: st,
      );
      return const <String>{};
    }
  }

  Future<Set<String>> _resolveBlockedIds({required String requestUid}) async {
    final cached = ref.read(blockedUsersProvider).value;
    if (cached != null) return cached.toSet();
    try {
      final wait = ref.read(feedDependencyMaxWaitProvider);
      final resolved = await ref
          .read(blockedUsersProvider.future)
          .timeout(wait);
      final liveUid = ref.read(firebaseAuthProvider).currentUser?.uid;
      if (liveUid != requestUid) return const <String>{};
      return resolved.toSet();
    } on TimeoutException {
      log(
        'blockedUsersProvider timed out during feed fetch; using empty fallback',
        name: 'FeedController',
      );
      return const <String>{};
    } catch (e, st) {
      log(
        'blockedUsersProvider unavailable during feed fetch; using empty fallback',
        name: 'FeedController',
        error: e,
        stackTrace: st,
      );
      return const <String>{};
    }
  }

  void _applyRefreshFreshnessPin() {
    if (_surface != FeedSurface.home) return;
    final current = state.value;
    if (current == null || current.items.length < 2) return;
    final windowEnd =
        current.items.length < _refreshFreshnessWindowSize
            ? current.items.length
            : _refreshFreshnessWindowSize;
    final head = [...current.items.take(windowEnd)];
    head.sort((a, b) {
      final aMs = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bMs = b.createdAt?.millisecondsSinceEpoch ?? 0;
      final byTime = bMs.compareTo(aMs);
      if (byTime != 0) return byTime;
      return a.id.compareTo(b.id);
    });
    final nextItems = <RankedPost>[...head, ...current.items.skip(windowEnd)];
    state = AsyncData(current.copyWith(items: nextItems));
  }

  void updatePostLikeOptimistic({
    required String postId,
    required String userId,
    required bool liked,
    required int likes,
    bool nudgeLocalRank = true,
  }) {
    final current = state.value;
    if (current == null) return;
    final index = current.items.indexWhere((p) => p.id == postId);
    if (index < 0) return;

    final nextItems = [...current.items];
    final target = current.items[index];
    final nextRaw = Map<String, dynamic>.from(target.raw);
    final likedBySet =
        ((nextRaw['likedBy'] as List?) ?? const <dynamic>[])
            .whereType<String>()
            .toSet();

    if (liked) {
      likedBySet.add(userId);
    } else {
      likedBySet.remove(userId);
    }

    final safeLikes = likes < 0 ? 0 : likes;
    nextRaw['likedBy'] = likedBySet.toList(growable: false);
    nextRaw['likes'] = safeLikes;

    final baseRank =
        target.serverRankScore ?? (nextRaw['rankScore'] as num?)?.toDouble();
    final rankDelta =
        nudgeLocalRank
            ? (liked ? _localLikeRankDelta : -_localLikeRankDelta)
            : 0.0;
    final nextRank = baseRank == null ? null : (baseRank + rankDelta);
    if (nextRank != null) {
      nextRaw['rankScore'] = nextRank;
    }

    nextItems[index] = RankedPost(
      id: target.id,
      authorId: target.authorId,
      createdAt: target.createdAt,
      likes: safeLikes,
      commentsCount: target.commentsCount,
      hashtags: target.hashtags,
      ownerIsPrivate: target.ownerIsPrivate,
      serverRankScore: nextRank ?? target.serverRankScore,
      raw: nextRaw,
    );

    state = AsyncData(current.copyWith(items: nextItems, rankingDirty: true));
    _scheduleSilentRankReconcile();
  }

  void maybeApplyDeferredReorder({required bool atTopBoundary}) {
    if (_surface != FeedSurface.home || !atTopBoundary) return;
    final current = state.value;
    if (current == null ||
        !current.pendingReorder ||
        current.items.length < 2) {
      return;
    }
    _rerankCurrentSession(current);
  }

  Future<void> _rerankCurrentSession(FeedState current) async {
    final meUid = ref.read(authStateProvider).asData?.value?.uid;
    if (meUid == null) return;
    final followingIds = await ref.read(followingIdsProvider.future);
    final policy = ref.read(rankingPolicyProvider);
    final flag = ref.read(rankingFeatureFlagProvider);
    final weights =
        flag == RankingFlag.disabled
            ? RankingWeights.legacy
            : RankingWeights.forSurface(_surface);
    final reranked = policy.rerank(
      current.items,
      RankingContext(
        surface: _surface,
        weights: weights,
        followingIds: followingIds,
        now: DateTime.now(),
        sessionSeed: current.sessionSeed,
      ),
    );
    state = AsyncData(current.copyWith(items: reranked, pendingReorder: false));
  }

  void _scheduleSilentRankReconcile() {
    if (_surface != FeedSurface.home) return;
    _rankReconcileTimer?.cancel();
    _rankReconcileTimer = Timer(_rankReconcileDebounce, () async {
      await _runSilentRankReconcile();
    });
  }

  Future<void> _runSilentRankReconcile() async {
    if (_rankReconcileInFlight) return;
    final snapshot = state.value;
    if (snapshot == null || snapshot.items.isEmpty) return;
    _rankReconcileInFlight = true;
    try {
      final ids = snapshot.items.map((e) => e.id).toList(growable: false);
      final freshById = await ref
          .read(boomerangRepoProvider)
          .fetchBoomerangFieldsByIds(ids);
      if (freshById.isEmpty) return;
      final live = state.value;
      if (live == null || live.items.isEmpty) return;

      final nextItems = <RankedPost>[];
      for (final post in live.items) {
        final fresh = freshById[post.id];
        if (fresh == null) {
          nextItems.add(post);
          continue;
        }
        final nextRaw = Map<String, dynamic>.from(post.raw);
        if (fresh.containsKey('likedBy')) {
          nextRaw['likedBy'] = ((fresh['likedBy'] as List?) ??
                  const <dynamic>[])
              .whereType<String>()
              .toList(growable: false);
        }
        if (fresh.containsKey('likes')) {
          final likes = (fresh['likes'] as num?)?.toInt() ?? post.likes;
          nextRaw['likes'] = likes < 0 ? 0 : likes;
        }
        final score = (fresh['rankScore'] as num?)?.toDouble();
        if (score != null) {
          nextRaw['rankScore'] = score;
        }
        nextItems.add(
          RankedPost(
            id: post.id,
            authorId: post.authorId,
            createdAt: post.createdAt,
            likes: ((nextRaw['likes'] ?? post.likes) as num).toInt(),
            commentsCount: post.commentsCount,
            hashtags: post.hashtags,
            ownerIsPrivate: post.ownerIsPrivate,
            serverRankScore: score ?? post.serverRankScore,
            raw: nextRaw,
          ),
        );
      }

      state = AsyncData(
        live.copyWith(
          items: nextItems,
          rankingDirty: false,
          pendingReorder: true,
        ),
      );
    } finally {
      _rankReconcileInFlight = false;
    }
  }

  Future<CandidatePool> _fetchPool({
    required FeedRepo repo,
    required FeedCursor? cursor,
    required String myUid,
    required Set<String> followingIds,
    required Set<String> blockedIds,
  }) {
    switch (_surface) {
      case FeedSurface.home:
        return repo.fetchHomeCandidates(
          myUid: myUid,
          followingIds: followingIds,
          blockedIds: blockedIds,
          cursor: cursor is HomeCursor ? cursor : null,
        );
      case FeedSurface.discovery:
        return repo.fetchDiscoveryCandidates(
          myUid: myUid,
          blockedIds: blockedIds,
          cursor: cursor is DiscoveryCursor ? cursor : null,
        );
    }
  }
}

final feedControllerProvider =
    AsyncNotifierProvider.family<FeedController, FeedState, FeedSurface>(
      FeedController.new,
    );
