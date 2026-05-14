import 'package:boomerang/features/profile/domain/follow_privacy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public follow executes immediately', () {
    final decision = decideFollowAction(
      targetIsPrivate: false,
      alreadyFollowing: false,
    );
    expect(decision, FollowDecision.followNow);
  });

  test('private follow creates request', () {
    final decision = decideFollowAction(
      targetIsPrivate: true,
      alreadyFollowing: false,
    );
    expect(decision, FollowDecision.createRequest);
  });

  test('approve transitions requested -> approved', () {
    final next = nextFollowState(
      current: FollowState.requested,
      transition: FollowTransition.approve,
    );
    expect(next, FollowState.approved);
  });

  test('reject transitions requested -> removed', () {
    final next = nextFollowState(
      current: FollowState.requested,
      transition: FollowTransition.reject,
    );
    expect(next, FollowState.removed);
  });

  test('block always wins and unblock returns to none', () {
    final blocked = nextFollowState(
      current: FollowState.approved,
      transition: FollowTransition.block,
    );
    final unblocked = nextFollowState(
      current: blocked,
      transition: FollowTransition.unblock,
    );
    expect(blocked, FollowState.blocked);
    expect(unblocked, FollowState.none);
  });

  test('privacy toggle to public auto-accepts pending', () {
    final autoAccept = shouldAutoAcceptPendingOnPublicSwitch(
      newIsPrivate: false,
    );
    expect(autoAccept, true);
  });
}
