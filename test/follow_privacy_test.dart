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

  test('accept from inbox transitions pending -> accepted', () {
    final next = nextRequestStatus(
      FollowRequestStatus.pending,
      FollowRequestAction.accept,
    );
    expect(next, FollowRequestStatus.accepted);
  });

  test('reject flow transitions pending -> rejected', () {
    final next = nextRequestStatus(
      FollowRequestStatus.pending,
      FollowRequestAction.reject,
    );
    expect(next, FollowRequestStatus.rejected);
  });

  test('privacy toggle to public auto-accepts pending', () {
    final autoAccept = shouldAutoAcceptPendingOnPublicSwitch(
      newIsPrivate: false,
    );
    expect(autoAccept, true);
  });
}
