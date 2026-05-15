import 'package:boomerang/infrastructure/providers.dart';
import 'package:boomerang/features/profile/infrastructure/user_profile_repo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ProfileRefreshStatus {
  idle,
  refreshedFromServer,
  refreshedFromServerAndCache,
  refreshedFromCacheFallback,
  failed,
}

class ProfileRefreshFetchResult {
  const ProfileRefreshFetchResult({required this.status, this.errorMessage});

  final ProfileRefreshStatus status;
  final String? errorMessage;
}

typedef ProfileRefreshFetcher =
    Future<ProfileRefreshFetchResult> Function(
      String userId, {
      required bool forceRefresh,
    });

typedef ProfileRefreshInvalidator =
    void Function(Ref ref, String userId, String? me);

class ProfileRefreshState {
  const ProfileRefreshState({
    this.lastRefreshAt = const <String, DateTime>{},
    this.pendingSocialMutation = const <String>{},
    this.lastRefreshStatus = const <String, ProfileRefreshStatus>{},
    this.lastRefreshError = const <String, String?>{},
  });

  final Map<String, DateTime> lastRefreshAt;
  final Set<String> pendingSocialMutation;
  final Map<String, ProfileRefreshStatus> lastRefreshStatus;
  final Map<String, String?> lastRefreshError;

  ProfileRefreshState copyWith({
    Map<String, DateTime>? lastRefreshAt,
    Set<String>? pendingSocialMutation,
    Map<String, ProfileRefreshStatus>? lastRefreshStatus,
    Map<String, String?>? lastRefreshError,
  }) {
    return ProfileRefreshState(
      lastRefreshAt: lastRefreshAt ?? this.lastRefreshAt,
      pendingSocialMutation:
          pendingSocialMutation ?? this.pendingSocialMutation,
      lastRefreshStatus: lastRefreshStatus ?? this.lastRefreshStatus,
      lastRefreshError: lastRefreshError ?? this.lastRefreshError,
    );
  }
}

class ProfileRefreshController extends StateNotifier<ProfileRefreshState> {
  ProfileRefreshController(this.ref) : super(const ProfileRefreshState());

  final Ref ref;
  final Map<String, Future<void>> _inFlightByUserId = <String, Future<void>>{};

  static const Duration defaultStaleAfter = Duration(seconds: 45);

  Future<void> onProfileOpened(
    String userId, {
    Duration staleAfter = defaultStaleAfter,
  }) async {
    if (userId.isEmpty) return;
    final me = ref.read(currentUserProfileProvider).value?.uid;
    final isSelf = me != null && me == userId;
    final last = state.lastRefreshAt[userId];
    final isStale =
        last == null || DateTime.now().difference(last) > staleAfter;
    final socialMutationPending = state.pendingSocialMutation.contains(userId);

    if (isSelf) {
      // Self profile relies on live stream and generally does not need forced
      // fetch on open unless an action marked it as dirty.
      if (!socialMutationPending) return;
    }

    if (isStale || socialMutationPending) {
      await refreshProfile(
        userId,
        forceRefresh: socialMutationPending || !isSelf,
      );
    }
  }

  Future<void> refreshProfile(String userId, {bool forceRefresh = true}) {
    if (userId.isEmpty) return Future<void>.value();
    final inFlight = _inFlightByUserId[userId];
    if (inFlight != null) return inFlight;

    final future = _performRefresh(userId, forceRefresh: forceRefresh);
    _inFlightByUserId[userId] = future;
    future.whenComplete(() {
      _inFlightByUserId.remove(userId);
    });
    return future;
  }

  void markSocialMutation(String userId) {
    if (userId.isEmpty) return;
    final pending = <String>{...state.pendingSocialMutation, userId};
    state = state.copyWith(pendingSocialMutation: pending);
  }

  void markAuthoritativeSync(Iterable<String> userIds) {
    final pending = <String>{...state.pendingSocialMutation};
    final refreshedAt = <String, DateTime>{...state.lastRefreshAt};
    final statuses = <String, ProfileRefreshStatus>{...state.lastRefreshStatus};
    final errors = <String, String?>{...state.lastRefreshError};
    final now = DateTime.now();
    for (final userId in userIds) {
      if (userId.isEmpty) continue;
      pending.remove(userId);
      refreshedAt[userId] = now;
      statuses[userId] = ProfileRefreshStatus.refreshedFromServer;
      errors[userId] = null;
    }
    state = state.copyWith(
      pendingSocialMutation: pending,
      lastRefreshAt: refreshedAt,
      lastRefreshStatus: statuses,
      lastRefreshError: errors,
    );
  }

  Future<void> _performRefresh(
    String userId, {
    required bool forceRefresh,
  }) async {
    late final ProfileRefreshFetchResult fetchResult;
    try {
      fetchResult = await ref
          .read(profileRefreshFetcherProvider)
          .call(userId, forceRefresh: forceRefresh);
    } catch (error) {
      fetchResult = ProfileRefreshFetchResult(
        status: ProfileRefreshStatus.failed,
        errorMessage: error.toString(),
      );
    }

    final me = ref.read(currentUserProfileProvider).value?.uid;
    ref.read(profileRefreshInvalidatorProvider).call(ref, userId, me);

    final nextTimes = <String, DateTime>{...state.lastRefreshAt};
    if (fetchResult.status != ProfileRefreshStatus.failed) {
      nextTimes[userId] = DateTime.now();
    }
    final pending = <String>{...state.pendingSocialMutation};
    if (fetchResult.status != ProfileRefreshStatus.failed) {
      pending.remove(userId);
    }
    final nextStatus = <String, ProfileRefreshStatus>{
      ...state.lastRefreshStatus,
      userId: fetchResult.status,
    };
    final nextErrors = <String, String?>{
      ...state.lastRefreshError,
      userId: fetchResult.errorMessage,
    };
    state = state.copyWith(
      lastRefreshAt: nextTimes,
      pendingSocialMutation: pending,
      lastRefreshStatus: nextStatus,
      lastRefreshError: nextErrors,
    );
  }
}

final profileRefreshControllerProvider =
    StateNotifierProvider<ProfileRefreshController, ProfileRefreshState>(
      (ref) => ProfileRefreshController(ref),
    );

final profileRefreshStatusProvider =
    Provider.family<ProfileRefreshStatus, String>((ref, userId) {
      return ref.watch(
        profileRefreshControllerProvider.select(
          (state) =>
              state.lastRefreshStatus[userId] ?? ProfileRefreshStatus.idle,
        ),
      );
    });

final profileRefreshErrorProvider = Provider.family<String?, String>((
  ref,
  userId,
) {
  return ref.watch(
    profileRefreshControllerProvider.select(
      (state) => state.lastRefreshError[userId],
    ),
  );
});

final profileRefreshFetcherProvider = Provider<ProfileRefreshFetcher>((ref) {
  return (String userId, {required bool forceRefresh}) async {
    final result = await ref
        .read(userProfileRepoProvider)
        .getProfileWithTelemetry(userId, forceRefresh: forceRefresh);
    switch (result.status) {
      case UserProfileFetchStatus.serverData:
        return const ProfileRefreshFetchResult(
          status: ProfileRefreshStatus.refreshedFromServer,
        );
      case UserProfileFetchStatus.serverAndCacheData:
        return const ProfileRefreshFetchResult(
          status: ProfileRefreshStatus.refreshedFromServerAndCache,
        );
      case UserProfileFetchStatus.cacheFallbackData:
        return const ProfileRefreshFetchResult(
          status: ProfileRefreshStatus.refreshedFromCacheFallback,
        );
      case UserProfileFetchStatus.failed:
        return ProfileRefreshFetchResult(
          status: ProfileRefreshStatus.failed,
          errorMessage: result.error?.toString(),
        );
    }
  };
});

final profileRefreshInvalidatorProvider = Provider<ProfileRefreshInvalidator>((
  ref,
) {
  return (ref, userId, me) {
    ref.invalidate(userProfileByIdProvider(userId));
    ref.invalidate(followersCountProvider(userId));
    ref.invalidate(followingCountProvider(userId));
    ref.invalidate(userBoomerangsCountProvider(userId));
    ref.invalidate(userTotalLikesProvider(userId));
    ref.invalidate(isFollowingStreamProvider(userId));
    ref.invalidate(outgoingFollowRequestProvider(userId));
    ref.invalidate(incomingFollowRequestProvider(userId));

    if (me != null && me.isNotEmpty) {
      ref.invalidate(currentUserProfileProvider);
      ref.invalidate(userProfileByIdProvider(me));
      ref.invalidate(followersCountProvider(me));
      ref.invalidate(followingCountProvider(me));
      ref.invalidate(followingIdsProvider);
    }
  };
});
