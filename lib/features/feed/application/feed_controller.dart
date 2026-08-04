import 'dart:async';
import 'dart:developer' show log;

import 'package:boomerang/core/feed/feed_debug.dart';
import 'package:boomerang/core/utils/perf_log.dart';
import 'package:firebase_core/firebase_core.dart';
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
    required this.buffer,
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

  /// Candidates fetched from the source but not yet emitted into [items].
  /// They are drained a page at a time before the source cursor advances,
  /// so a fetch that returns more candidates than a page can never silently
  /// drop the overflow.
  final List<RankedPost> buffer;
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
    List<RankedPost>? buffer,
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
      buffer: buffer ?? this.buffer,
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
    buffer: <RankedPost>[],
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
  Timer? _transientRetryTimer;
  bool _rankReconcileInFlight = false;
  bool _bootFetchScheduled = false;
  int _consecutiveFetchFailures = 0;

  @override
  Future<FeedState> build(FeedSurface arg) async {
    _surface = arg;
    ref.onDispose(() {
      _rankReconcileTimer?.cancel();
      _transientRetryTimer?.cancel();
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

  bool _isTransientFetchError(Object error) {
    if (error is TimeoutException) return true;
    if (error is! FirebaseException) return false;
    switch (error.code) {
      case 'permission-denied':
      case 'unauthenticated':
      case 'network-request-failed':
      case 'unavailable':
      case 'aborted':
      case 'deadline-exceeded':
      case 'failed-precondition':
        return true;
      default:
        return false;
    }
  }

  void _scheduleTransientRetry() {
    _transientRetryTimer?.cancel();
    _transientRetryTimer = Timer(const Duration(milliseconds: 700), () {
      unawaited(fetchNext());
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
    if (current.isLoading) return;
    // Nothing more to show only when the source is drained AND there are no
    // buffered candidates left to emit.
    if (!current.hasMore && current.buffer.isEmpty) return;

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
      final fetchClock = Stopwatch()..start();
      log(
        '[FEEDDBG] fetchNext ENTER surface=${_surface.name} uid=$requestUid '
        'page=${current.pageIndex} buffer=${current.buffer.length} '
        'seen=${current.seenIds.length} hasMore=${current.hasMore} '
        'cursor=${current.nextCursor.runtimeType}',
        name: 'FeedController',
      );
      final deps = await PerfLog.track(
        'feed.resolveDeps',
        () => Future.wait([
          _resolveFollowingIds(requestUid: requestUid),
          _resolveBlockedIds(requestUid: requestUid),
        ]),
        detail: 'surface=${_surface.name} page=${current.pageIndex}',
      );
      final followingIds = deps[0];
      final blockedIds = deps[1];
      if (kFeedDebug) {
        log(
          '[FEEDDBG] deps resolved surface=${_surface.name} '
          'following=${followingIds.length} blocked=${blockedIds.length}',
          name: 'FeedController',
        );
      }
      final liveUidAfterDeps = ref.read(firebaseAuthProvider).currentUser?.uid;
      if (liveUidAfterDeps != requestUid) {
        log(
          '[FEEDDBG] uid changed after deps ($requestUid -> $liveUidAfterDeps); '
          'aborting fetch',
          name: 'FeedController',
        );
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

      var buffer = current.buffer;
      var nextCursor = current.nextCursor;
      var sourceHasMore = current.hasMore;

      // Only hit the network when the buffer can't fill a page and the source
      // still has candidates. The source cursor advances solely by the page
      // we fetch here — never past buffered-but-unshown posts — so a pool that
      // returns more candidates than `_pageSize` no longer drops the overflow.
      if (buffer.length < _pageSize && sourceHasMore) {
        final repo = ref.read(feedRepoProvider);
        log(
          '[FEEDDBG] fetching pool surface=${_surface.name} '
          'cursor=${nextCursor.runtimeType}',
          name: 'FeedController',
        );
        final pool = await PerfLog.track(
          'feed.fetchPool',
          () => _fetchPool(
            repo: repo,
            cursor: nextCursor,
            myUid: requestUid,
            followingIds: followingIds,
            blockedIds: blockedIds,
          ),
          detail:
              'surface=${_surface.name} page=${current.pageIndex} '
              'following=${followingIds.length}',
        );
        log(
          '[FEEDDBG] pool OK surface=${_surface.name} '
          'posts=${pool.posts.length} hasMore=${pool.hasMore} '
          'nextCursor=${pool.nextCursor.runtimeType}',
          name: 'FeedController',
        );
        final liveUidAfterFetch =
            ref.read(firebaseAuthProvider).currentUser?.uid;
        if (liveUidAfterFetch != requestUid) {
          state = AsyncData(current.copyWith(isLoading: false));
          return;
        }
        // Drop anything already shown or already buffered.
        final known = <String>{
          ...current.seenIds,
          ...buffer.map((p) => p.id),
        };
        final freshFromPool = pool.posts
            .where((p) => !known.contains(p.id))
            .toList(growable: false);
        buffer = <RankedPost>[...buffer, ...freshFromPool];
        nextCursor = pool.nextCursor;
        sourceHasMore = pool.hasMore;
      }

      // Re-rank the full buffer using the policy + previously-shown tail for
      // cross-page burst control, emit one page, keep the remainder buffered.
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
      final ranked = policy.rerank(buffer, context);
      final pageSlice = ranked.take(_pageSize).toList(growable: false);
      final remaining =
          ranked.length > _pageSize
              ? ranked.sublist(_pageSize)
              : const <RankedPost>[];

      final mergedItems = <RankedPost>[...current.items, ...pageSlice];
      final mergedSeen = <String>{
        ...current.seenIds,
        ...pageSlice.map((p) => p.id),
      };

      final hasMore = sourceHasMore || remaining.isNotEmpty;

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
          buffer: remaining,
          nextCursor: nextCursor,
          clearCursor: nextCursor == null,
          hasMore: hasMore,
          isLoading: false,
          seenIds: mergedSeen,
          pageIndex: current.pageIndex + 1,
          rankingVersion: rankingVersion,
        ),
      );
      PerfLog.event(
        'feed PAGE-READY',
        'surface=${_surface.name} page=${current.pageIndex} '
            'emitted=${pageSlice.length} totalItems=${mergedItems.length} '
            'took=${fetchClock.elapsedMilliseconds}ms',
      );
      _consecutiveFetchFailures = 0;
    } catch (e, st) {
      _consecutiveFetchFailures++;
      // Detailed diagnostics so intermittent / data-dependent failures that
      // only repro on certain accounts can be root-caused from logs.
      final firebaseInfo =
          e is FirebaseException
              ? 'FirebaseException plugin=${e.plugin} code=${e.code} '
                  'message=${e.message}'
              : 'type=${e.runtimeType}';
      log(
        '[FEEDDBG] fetchNext ERROR surface=${_surface.name} '
        'attempt=$_consecutiveFetchFailures '
        'transient=${_isTransientFetchError(e)} $firebaseInfo',
        name: 'FeedController',
        error: e,
        stackTrace: st,
      );
      final shouldRetryTransiently =
          _consecutiveFetchFailures <= 2 && _isTransientFetchError(e);
      if (shouldRetryTransiently) {
        log(
          '[FEEDDBG] transient failure; scheduling retry '
          '(attempt $_consecutiveFetchFailures)',
          name: 'FeedController',
        );
        state = AsyncData(current.copyWith(isLoading: false));
        _scheduleTransientRetry();
        return;
      }
      log(
        '[FEEDDBG] fetchNext SURFACING error to UI (error screen) '
        'surface=${_surface.name} $firebaseInfo',
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
