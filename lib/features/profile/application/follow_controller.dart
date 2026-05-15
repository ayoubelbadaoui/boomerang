import 'package:boomerang/features/profile/domain/follow_privacy.dart';
import 'package:boomerang/features/profile/application/profile_refresh_controller.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:boomerang/features/profile/domain/follow_privacy.dart';

class FollowFlowState {
  const FollowFlowState({
    this.inFlightUserIds = const <String>{},
    this.optimisticStates = const <String, FollowState>{},
    this.optimisticCountPatches = const <String, SocialCountPatch>{},
    this.optimisticallyResolvedIncoming = const <String>{},
  });

  final Set<String> inFlightUserIds;
  final Map<String, FollowState> optimisticStates;
  final Map<String, SocialCountPatch> optimisticCountPatches;
  final Set<String> optimisticallyResolvedIncoming;

  FollowFlowState copyWith({
    Set<String>? inFlightUserIds,
    Map<String, FollowState>? optimisticStates,
    Map<String, SocialCountPatch>? optimisticCountPatches,
    Set<String>? optimisticallyResolvedIncoming,
  }) {
    return FollowFlowState(
      inFlightUserIds: inFlightUserIds ?? this.inFlightUserIds,
      optimisticStates: optimisticStates ?? this.optimisticStates,
      optimisticCountPatches:
          optimisticCountPatches ?? this.optimisticCountPatches,
      optimisticallyResolvedIncoming:
          optimisticallyResolvedIncoming ?? this.optimisticallyResolvedIncoming,
    );
  }
}

class SocialCountPatch {
  const SocialCountPatch({this.followersDelta = 0, this.followingDelta = 0});

  final int followersDelta;
  final int followingDelta;

  SocialCountPatch copyWith({int? followersDelta, int? followingDelta}) {
    return SocialCountPatch(
      followersDelta: followersDelta ?? this.followersDelta,
      followingDelta: followingDelta ?? this.followingDelta,
    );
  }

  bool get isZero => followersDelta == 0 && followingDelta == 0;
}

class ProfileSocialState {
  const ProfileSocialState({
    required this.followerCount,
    required this.followingCount,
    required this.followRelationshipStatus,
  });

  final int followerCount;
  final int followingCount;
  final FollowState followRelationshipStatus;
}

class FollowFlowController extends StateNotifier<FollowFlowState> {
  FollowFlowController(this.ref) : super(const FollowFlowState());

  final Ref ref;

  bool isInFlight(String userId) => state.inFlightUserIds.contains(userId);

  Future<void> toggleRelationship({
    required String targetUserId,
    required bool targetIsPrivate,
    required FollowState currentState,
  }) async {
    if (targetUserId.isEmpty || isInFlight(targetUserId)) return;
    final previousState = state;
    _setInFlight(targetUserId, true);
    final me = ref.read(firebaseAuthProvider).currentUser?.uid;

    final repo = ref.read(followRepoProvider);
    try {
      switch (currentState) {
        case FollowState.approved:
          _setOptimistic(targetUserId, FollowState.none);
          _adjustCounts(targetUserId, followersDelta: -1);
          if (me != null && me.isNotEmpty) {
            _adjustCounts(me, followingDelta: -1);
          }
          final serverState = await repo.unfollowWithServerState(targetUserId);
          _setOptimistic(targetUserId, serverState.relationshipStatus);
          await _reconcileAfterRelationshipMutation(
            targetUserId: targetUserId,
            impactedUserIds: {
              targetUserId,
              if (me != null && me.isNotEmpty) me,
            },
            serverState: serverState,
          );
          break;
        case FollowState.requested:
          _setOptimistic(targetUserId, FollowState.none);
          await repo.cancelRequest(targetUserId);
          await _reconcileAfterRelationshipMutation(
            targetUserId: targetUserId,
            impactedUserIds: {
              targetUserId,
              if (me != null && me.isNotEmpty) me,
            },
          );
          break;
        case FollowState.none:
        case FollowState.removed:
          _setOptimistic(
            targetUserId,
            targetIsPrivate ? FollowState.requested : FollowState.approved,
          );
          if (!targetIsPrivate) {
            _adjustCounts(targetUserId, followersDelta: 1);
            if (me != null && me.isNotEmpty) {
              _adjustCounts(me, followingDelta: 1);
            }
          }
          final serverState = await repo.followOrRequestWithServerState(
            targetUserId,
          );
          _setOptimistic(targetUserId, serverState.relationshipStatus);
          await _reconcileAfterRelationshipMutation(
            targetUserId: targetUserId,
            impactedUserIds: {
              targetUserId,
              if (me != null && me.isNotEmpty) me,
            },
            serverState: serverState,
          );
          break;
        case FollowState.blocked:
          break;
      }
    } catch (_) {
      state = previousState;
      rethrow;
    } finally {
      _setInFlight(targetUserId, false);
    }
  }

  Future<void> approveIncomingRequest({
    required String senderId,
    String? notificationId,
  }) async {
    if (senderId.isEmpty || isInFlight(senderId)) return;
    final previousState = state;
    _setInFlight(senderId, true);
    final me = ref.read(firebaseAuthProvider).currentUser?.uid;
    try {
      final senderAlreadyFollowsMe =
          ref.read(isFollowedByProvider(senderId)).value ?? false;
      _setIncomingResolved(senderId, true);
      if (!senderAlreadyFollowsMe) {
        _adjustCounts(senderId, followingDelta: 1);
        if (me != null && me.isNotEmpty) {
          _adjustCounts(me, followersDelta: 1);
        }
      }
      final serverState = await ref
          .read(followRepoProvider)
          .acceptRequestWithServerState(
            senderId: senderId,
            notificationId: notificationId,
          );
      await _reconcileAfterRelationshipMutation(
        targetUserId: senderId,
        impactedUserIds: {senderId, if (me != null && me.isNotEmpty) me},
        clearIncomingResolution: true,
        serverState: serverState,
      );
    } catch (_) {
      state = previousState;
      rethrow;
    } finally {
      _setInFlight(senderId, false);
    }
  }

  Future<void> rejectIncomingRequest({
    required String senderId,
    String? notificationId,
  }) async {
    if (senderId.isEmpty || isInFlight(senderId)) return;
    final previousState = state;
    _setInFlight(senderId, true);
    final me = ref.read(firebaseAuthProvider).currentUser?.uid;
    try {
      final senderAlreadyFollowsMe =
          ref.read(isFollowedByProvider(senderId)).value ?? false;
      _setIncomingResolved(senderId, true);
      if (senderAlreadyFollowsMe) {
        _adjustCounts(senderId, followingDelta: -1);
        if (me != null && me.isNotEmpty) {
          _adjustCounts(me, followersDelta: -1);
        }
      }
      final serverState = await ref
          .read(followRepoProvider)
          .rejectRequestWithServerState(
            senderId: senderId,
            notificationId: notificationId,
          );
      await _reconcileAfterRelationshipMutation(
        targetUserId: senderId,
        impactedUserIds: {senderId, if (me != null && me.isNotEmpty) me},
        clearIncomingResolution: true,
        serverState: serverState,
      );
    } catch (_) {
      state = previousState;
      rethrow;
    } finally {
      _setInFlight(senderId, false);
    }
  }

  void _setInFlight(String userId, bool value) {
    final next = <String>{...state.inFlightUserIds};
    if (value) {
      next.add(userId);
    } else {
      next.remove(userId);
    }
    state = state.copyWith(inFlightUserIds: next);
  }

  void _setOptimistic(String userId, FollowState value) {
    final next = <String, FollowState>{...state.optimisticStates};
    next[userId] = value;
    state = state.copyWith(optimisticStates: next);
  }

  void _setIncomingResolved(String userId, bool value) {
    final next = <String>{...state.optimisticallyResolvedIncoming};
    if (value) {
      next.add(userId);
    } else {
      next.remove(userId);
    }
    state = state.copyWith(optimisticallyResolvedIncoming: next);
  }

  void _adjustCounts(
    String userId, {
    int followersDelta = 0,
    int followingDelta = 0,
  }) {
    if (userId.isEmpty || (followersDelta == 0 && followingDelta == 0)) return;
    final next = <String, SocialCountPatch>{...state.optimisticCountPatches};
    final existing = next[userId] ?? const SocialCountPatch();
    final patch = existing.copyWith(
      followersDelta: existing.followersDelta + followersDelta,
      followingDelta: existing.followingDelta + followingDelta,
    );
    if (patch.isZero) {
      next.remove(userId);
    } else {
      next[userId] = patch;
    }
    state = state.copyWith(optimisticCountPatches: next);
  }

  void _clearOptimistic(String userId) {
    if (!state.optimisticStates.containsKey(userId)) return;
    final next = <String, FollowState>{...state.optimisticStates};
    next.remove(userId);
    state = state.copyWith(optimisticStates: next);
  }

  void _clearCountPatches(Iterable<String> userIds) {
    final next = <String, SocialCountPatch>{...state.optimisticCountPatches};
    var didChange = false;
    for (final userId in userIds) {
      if (next.remove(userId) != null) {
        didChange = true;
      }
    }
    if (!didChange) return;
    state = state.copyWith(optimisticCountPatches: next);
  }

  Future<void> _reconcileAfterRelationshipMutation({
    required String targetUserId,
    required Set<String> impactedUserIds,
    bool clearIncomingResolution = false,
    FollowMutationServerState? serverState,
  }) async {
    final refreshController = ref.read(
      profileRefreshControllerProvider.notifier,
    );
    if (serverState != null) {
      _reconcileOptimisticStateWithServer(
        targetUserId: targetUserId,
        currentUserId: ref.read(firebaseAuthProvider).currentUser?.uid,
        serverState: serverState,
      );
    }
    for (final userId in impactedUserIds) {
      refreshController.markSocialMutation(userId);
    }
    _invalidateAfterRelationshipMutation(targetUserId: targetUserId);
    if (serverState == null || !serverState.hasAuthoritativeCounts) {
      try {
        await Future.wait(
          impactedUserIds
              .where((userId) => userId.isNotEmpty)
              .map(
                (userId) => refreshController.refreshProfile(
                  userId,
                  forceRefresh: true,
                ),
              ),
        );
      } catch (_) {
        // Network refresh failures should not revert a mutation that already
        // succeeded server-side. Streams/invalidations will still reconcile.
      }
    } else {
      refreshController.markAuthoritativeSync(impactedUserIds);
    }

    _clearOptimistic(targetUserId);
    _clearCountPatches(impactedUserIds);
    if (clearIncomingResolution) {
      _setIncomingResolved(targetUserId, false);
    }
  }

  void _reconcileOptimisticStateWithServer({
    required String targetUserId,
    required String? currentUserId,
    required FollowMutationServerState serverState,
  }) {
    _setOptimistic(targetUserId, serverState.relationshipStatus);
    final targetCounts = serverState.targetCounts;
    if (targetCounts != null) {
      final displayed = _currentDisplayedCounts(targetUserId);
      _adjustCounts(
        targetUserId,
        followersDelta: targetCounts.followersCount - displayed.followerCount,
        followingDelta: targetCounts.followingCount - displayed.followingCount,
      );
    }

    final me = currentUserId;
    final meCounts = serverState.currentUserCounts;
    if (me != null && me.isNotEmpty && meCounts != null) {
      final displayedMe = _currentDisplayedCounts(me);
      _adjustCounts(
        me,
        followersDelta: meCounts.followersCount - displayedMe.followerCount,
        followingDelta: meCounts.followingCount - displayedMe.followingCount,
      );
    }
  }

  ({int followerCount, int followingCount}) _currentDisplayedCounts(
    String userId,
  ) {
    final me = ref.read(currentUserProfileProvider).value;
    final profile =
        me?.uid == userId
            ? me
            : ref.read(userProfileByIdProvider(userId)).value;
    final patch = state.optimisticCountPatches[userId];
    final followerCount =
        (profile?.followersCount ?? 0) + (patch?.followersDelta ?? 0);
    final followingCount =
        (profile?.followingCount ?? 0) + (patch?.followingDelta ?? 0);
    return (
      followerCount: followerCount < 0 ? 0 : followerCount,
      followingCount: followingCount < 0 ? 0 : followingCount,
    );
  }

  void _invalidateAfterRelationshipMutation({required String targetUserId}) {
    final me = ref.read(firebaseAuthProvider).currentUser?.uid;

    ref.invalidate(isFollowingStreamProvider(targetUserId));
    ref.invalidate(outgoingFollowRequestProvider(targetUserId));
    ref.invalidate(incomingFollowRequestProvider(targetUserId));
    ref.invalidate(userProfileByIdProvider(targetUserId));
    ref.invalidate(followersCountProvider(targetUserId));
    ref.invalidate(followingCountProvider(targetUserId));
    ref.invalidate(followingIdsProvider);

    if (me != null && me.isNotEmpty) {
      ref.invalidate(userProfileByIdProvider(me));
      ref.invalidate(followersCountProvider(me));
      ref.invalidate(followingCountProvider(me));
      ref.invalidate(notificationsStreamProvider(me));
    }
  }
}

final followFlowControllerProvider =
    StateNotifierProvider<FollowFlowController, FollowFlowState>(
      (ref) => FollowFlowController(ref),
    );

final isFollowActionInFlightProvider = Provider.family<bool, String>((
  ref,
  targetUserId,
) {
  return ref.watch(
    followFlowControllerProvider.select(
      (state) => state.inFlightUserIds.contains(targetUserId),
    ),
  );
});

final followStateProvider = Provider.family<FollowState, String>((
  ref,
  targetUserId,
) {
  if (targetUserId.isEmpty) return FollowState.none;

  final optimistic = ref.watch(
    followFlowControllerProvider.select(
      (state) => state.optimisticStates[targetUserId],
    ),
  );
  final isFollowing =
      ref.watch(isFollowingStreamProvider(targetUserId)).value ?? false;
  final outgoing = ref.watch(outgoingFollowRequestProvider(targetUserId)).value;
  final canonical =
      isFollowing
          ? FollowState.approved
          : (outgoing?.isPending == true
              ? FollowState.requested
              : FollowState.none);

  if (optimistic != null) return optimistic;
  return canonical;
});

final profileSocialStateProvider = Provider.family<ProfileSocialState, String>((
  ref,
  userId,
) {
  final me = ref.watch(currentUserProfileProvider).value;
  final profile =
      me?.uid == userId ? me : ref.watch(userProfileByIdProvider(userId)).value;
  final patch = ref.watch(
    followFlowControllerProvider.select(
      (s) => s.optimisticCountPatches[userId],
    ),
  );

  final followers =
      (profile?.followersCount ?? 0) + (patch?.followersDelta ?? 0);
  final following =
      (profile?.followingCount ?? 0) + (patch?.followingDelta ?? 0);

  return ProfileSocialState(
    followerCount: followers < 0 ? 0 : followers,
    followingCount: following < 0 ? 0 : following,
    followRelationshipStatus: ref.watch(followStateProvider(userId)),
  );
});

final incomingRequestPendingProvider = Provider.family<bool, String>((
  ref,
  senderId,
) {
  if (senderId.isEmpty) return false;
  final resolvedOptimistically = ref.watch(
    followFlowControllerProvider.select(
      (state) => state.optimisticallyResolvedIncoming.contains(senderId),
    ),
  );
  if (resolvedOptimistically) return false;
  final incoming = ref.watch(incomingFollowRequestProvider(senderId)).value;
  return incoming?.isPending == true;
});

String followButtonLabelForState(FollowState state) {
  switch (state) {
    case FollowState.approved:
      return 'Following';
    case FollowState.requested:
      return 'Requested';
    case FollowState.none:
    case FollowState.removed:
    case FollowState.blocked:
      return 'Follow';
  }
}
