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
bool shouldAutoAcceptPendingOnPublicSwitch({
  required bool newIsPrivate,
}) {
  return newIsPrivate == false;
}

enum FollowRequestStatus { none, pending, accepted, rejected }

enum FollowRequestAction { send, accept, reject }

/// Transition helper to keep follow-request flow deterministic and testable.
FollowRequestStatus nextRequestStatus(
  FollowRequestStatus current,
  FollowRequestAction action,
) {
  switch (action) {
    case FollowRequestAction.send:
      return FollowRequestStatus.pending;
    case FollowRequestAction.accept:
      if (current == FollowRequestStatus.pending) {
        return FollowRequestStatus.accepted;
      }
      return current;
    case FollowRequestAction.reject:
      if (current == FollowRequestStatus.pending) {
        return FollowRequestStatus.rejected;
      }
      return current;
  }
}
