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
  });

  final List<RankedPost> items;
  final FeedCursor? nextCursor;
  final bool hasMore;
  final bool isLoading;
  final int sessionSeed;
  final Set<String> seenIds;
  final int pageIndex;
  final String rankingVersion;

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
  );
}

/// One controller per [FeedSurface]. Maintains pagination, session seed,
/// dedup set, and ranking version. Presentation reads `state.value.items`
/// and calls `refresh()` / `fetchNext()`.
class FeedController
    extends FamilyAsyncNotifier<FeedState, FeedSurface> {
  static const int _pageSize = 20;
  static const FeedMetrics _metrics = FeedMetrics();

  late FeedSurface _surface;

  @override
  Future<FeedState> build(FeedSurface arg) async {
    _surface = arg;
    final me = await ref.watch(currentUserProfileProvider.future);
    final seed = SessionSeed.bootstrap(
      uid: me?.uid ?? 'anon',
      surface: arg.name,
    );
    final initial = FeedState.empty.copyWith(
      sessionSeed: seed.value,
      seenIds: <String>{},
      pageIndex: 0,
      hasMore: true,
      clearCursor: true,
    );
    // Kick off the first page so the UI never sees a permanently-empty state.
    Future.microtask(fetchNext);
    return initial;
  }

  Future<void> refresh() async {
    final me = await ref.read(currentUserProfileProvider.future);
    final rotated = SessionSeed.bootstrap(
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
    final next = state.value?.items ?? const <RankedPost>[];
    _metrics.recordRefresh(
      surface: _surface,
      previousPage: previous,
      thisPage: next,
    );
  }

  Future<void> fetchNext() async {
    final current = state.value;
    if (current == null) return;
    if (current.isLoading || !current.hasMore) return;

    state = AsyncData(current.copyWith(isLoading: true));

    try {
      final me = await ref.read(currentUserProfileProvider.future);
      if (me == null) {
        state = AsyncData(current.copyWith(isLoading: false, hasMore: false));
        return;
      }
      final followingIds =
          await ref.read(followingIdsProvider.future);
      final blockedList =
          await ref.read(blockedUsersProvider.future);
      final blockedIds = blockedList.toSet();
      final policy = ref.read(rankingPolicyProvider);
      final flag = ref.read(rankingFeatureFlagProvider);

      final useLegacy = flag == RankingFlag.disabled;
      final weights = useLegacy
          ? RankingWeights.legacy
          : RankingWeights.forSurface(_surface);
      final rankingVersion = useLegacy
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
      final tail = current.items.length > 5
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
