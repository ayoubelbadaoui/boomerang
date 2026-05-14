import 'package:boomerang/features/profile/domain/follow_privacy.dart';
import 'package:boomerang/features/profile/infrastructure/follow_repo.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:boomerang/features/profile/domain/follow_privacy.dart';

class FollowFlowState {
  const FollowFlowState({
    this.inFlightUserIds = const <String>{},
    this.optimisticStates = const <String, FollowState>{},
  });

  final Set<String> inFlightUserIds;
  final Map<String, FollowState> optimisticStates;

  FollowFlowState copyWith({
    Set<String>? inFlightUserIds,
    Map<String, FollowState>? optimisticStates,
  }) {
    return FollowFlowState(
      inFlightUserIds: inFlightUserIds ?? this.inFlightUserIds,
      optimisticStates: optimisticStates ?? this.optimisticStates,
    );
  }
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
    _setInFlight(targetUserId, true);

    final repo = ref.read(followRepoProvider);
    try {
      switch (currentState) {
        case FollowState.approved:
          _setOptimistic(targetUserId, FollowState.none);
          await repo.unfollow(targetUserId);
          break;
        case FollowState.requested:
          _setOptimistic(targetUserId, FollowState.none);
          await repo.cancelRequest(targetUserId);
          break;
        case FollowState.none:
        case FollowState.removed:
          _setOptimistic(
            targetUserId,
            targetIsPrivate ? FollowState.requested : FollowState.approved,
          );
          final outcome = await repo.followOrRequest(targetUserId);
          _setOptimistic(
            targetUserId,
            outcome == FollowOutcome.requested
                ? FollowState.requested
                : FollowState.approved,
          );
          break;
        case FollowState.blocked:
          break;
      }

      _invalidateAfterRelationshipMutation(targetUserId: targetUserId);
    } finally {
      _setInFlight(targetUserId, false);
      _clearOptimisticAfterDelay(targetUserId);
    }
  }

  Future<void> approveIncomingRequest({
    required String senderId,
    String? notificationId,
  }) async {
    if (senderId.isEmpty || isInFlight(senderId)) return;
    _setInFlight(senderId, true);
    try {
      await ref.read(followRepoProvider).acceptRequest(
            senderId: senderId,
            notificationId: notificationId,
          );
      _invalidateAfterRelationshipMutation(targetUserId: senderId);
    } finally {
      _setInFlight(senderId, false);
    }
  }

  Future<void> rejectIncomingRequest({
    required String senderId,
    String? notificationId,
  }) async {
    if (senderId.isEmpty || isInFlight(senderId)) return;
    _setInFlight(senderId, true);
    try {
      await ref.read(followRepoProvider).rejectRequest(
            senderId: senderId,
            notificationId: notificationId,
          );
      _invalidateAfterRelationshipMutation(targetUserId: senderId);
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

  void _clearOptimistic(String userId) {
    if (!state.optimisticStates.containsKey(userId)) return;
    final next = <String, FollowState>{...state.optimisticStates};
    next.remove(userId);
    state = state.copyWith(optimisticStates: next);
  }

  void _clearOptimisticAfterDelay(String userId) {
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted || isInFlight(userId)) return;
      _clearOptimistic(userId);
    });
  }

  void _invalidateAfterRelationshipMutation({required String targetUserId}) {
    final me = ref.read(currentUserProfileProvider).value?.uid;

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

final isFollowActionInFlightProvider = Provider.family<bool, String>(
  (ref, targetUserId) {
    return ref.watch(
      followFlowControllerProvider.select(
        (state) => state.inFlightUserIds.contains(targetUserId),
      ),
    );
  },
);

final followStateProvider = Provider.family<FollowState, String>((
  ref,
  targetUserId,
) {
  if (targetUserId.isEmpty) return FollowState.none;

  final inFlight = ref.watch(isFollowActionInFlightProvider(targetUserId));
  final optimistic = ref.watch(
    followFlowControllerProvider.select(
      (state) => state.optimisticStates[targetUserId],
    ),
  );
  final isFollowing = ref.watch(isFollowingStreamProvider(targetUserId)).value ??
      false;
  final outgoing = ref.watch(outgoingFollowRequestProvider(targetUserId)).value;
  final canonical = isFollowing
      ? FollowState.approved
      : (outgoing?.isPending == true ? FollowState.requested : FollowState.none);

  if (inFlight && optimistic != null) return optimistic;
  return canonical;
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
