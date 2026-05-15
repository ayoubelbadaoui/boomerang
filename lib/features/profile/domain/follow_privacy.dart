enum FollowState { none, requested, approved, removed, blocked }

enum FollowOutcome { followed, requested }

class SocialGraphCounts {
  const SocialGraphCounts({
    required this.followersCount,
    required this.followingCount,
  });

  final int followersCount;
  final int followingCount;
}

class FollowMutationServerState {
  const FollowMutationServerState({
    required this.relationshipStatus,
    this.targetCounts,
    this.currentUserCounts,
  });

  final FollowState relationshipStatus;
  final SocialGraphCounts? targetCounts;
  final SocialGraphCounts? currentUserCounts;

  bool get hasAuthoritativeCounts =>
      targetCounts != null && currentUserCounts != null;
}

enum FollowTransition {
  request,
  approve,
  reject,
  cancel,
  unfollow,
  remove,
  block,
  unblock,
}

/// Single source of truth for relationship state transitions.
///
/// `removed` intentionally covers both explicit rejects and cleanup removals.
FollowState nextFollowState({
  required FollowState current,
  required FollowTransition transition,
}) {
  switch (transition) {
    case FollowTransition.block:
      return FollowState.blocked;
    case FollowTransition.unblock:
      return current == FollowState.blocked ? FollowState.none : current;
    case FollowTransition.request:
      if (current == FollowState.none || current == FollowState.removed) {
        return FollowState.requested;
      }
      return current;
    case FollowTransition.approve:
      if (current == FollowState.requested) {
        return FollowState.approved;
      }
      return current;
    case FollowTransition.reject:
      if (current == FollowState.requested) {
        return FollowState.removed;
      }
      return current;
    case FollowTransition.cancel:
      if (current == FollowState.requested) {
        return FollowState.removed;
      }
      return current;
    case FollowTransition.unfollow:
      if (current == FollowState.approved) {
        return FollowState.removed;
      }
      return current;
    case FollowTransition.remove:
      if (current == FollowState.requested || current == FollowState.approved) {
        return FollowState.removed;
      }
      return current;
  }
}

enum FollowDecision { followNow, createRequest, noop }

/// Decide how to handle a follow tap given the target's privacy and current
/// relationship. Pure function for easy testing.
FollowDecision decideFollowAction({
  required bool targetIsPrivate,
  required bool alreadyFollowing,
}) {
  if (alreadyFollowing) return FollowDecision.noop;
  return targetIsPrivate
      ? FollowDecision.createRequest
      : FollowDecision.followNow;
}

/// When switching privacy from private to public, we auto-accept all pending
/// requests to mirror Instagram behavior. This helper is a documented decision
/// to make the rule testable.
bool shouldAutoAcceptPendingOnPublicSwitch({required bool newIsPrivate}) {
  return newIsPrivate == false;
}
