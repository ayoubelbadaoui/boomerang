import 'package:boomerang/features/profile/application/follow_controller.dart';
import 'package:boomerang/features/profile/infrastructure/follow_repo.dart';
import 'package:boomerang/infrastructure/providers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FollowFlowController integration', () {
    late FakeFirebaseFirestore fs;

    const requesterId = 'requester_uid';
    const targetId = 'private_target_uid';

    Future<void> seedUsers() async {
      await fs.collection('users').doc(requesterId).set({
        'nickname': 'Requester',
        'fullName': 'Requester User',
        'isPrivate': false,
        'followersCount': 0,
        'followingCount': 0,
      });
      await fs.collection('users').doc(targetId).set({
        'nickname': 'Target',
        'fullName': 'Private Target',
        'isPrivate': true,
        'followersCount': 0,
        'followingCount': 0,
      });
    }

    MockFirebaseAuth authFor(String uid) {
      return MockFirebaseAuth(
        mockUser: MockUser(uid: uid, email: '$uid@example.com'),
        signedIn: true,
      );
    }

    ProviderContainer containerFor(String uid) {
      return ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(fs),
          firebaseAuthProvider.overrideWithValue(authFor(uid)),
        ],
      );
    }

    Future<void> createApprovedEdge() async {
      await fs
          .collection('following')
          .doc(requesterId)
          .collection('users')
          .doc(targetId)
          .set({
            'userId': targetId,
            'userName': 'Target',
          });
      await fs
          .collection('followers')
          .doc(targetId)
          .collection('users')
          .doc(requesterId)
          .set({
            'userId': requesterId,
            'userName': 'Requester',
          });
      await fs.collection('users').doc(requesterId).set({
        'followingCount': 1,
      }, SetOptions(merge: true));
      await fs.collection('users').doc(targetId).set({
        'followersCount': 1,
      }, SetOptions(merge: true));
    }

    setUp(() async {
      fs = FakeFirebaseFirestore();
      await seedUsers();
    });

    test('approve invalidates cached counts and refreshes to approved values', () async {
      final requesterRepo = FollowRepo(fs, authFor(requesterId));
      await requesterRepo.followOrRequest(targetId);

      final targetContainer = containerFor(targetId);
      addTearDown(targetContainer.dispose);

      expect(
        await targetContainer.read(followingCountProvider(requesterId).future),
        0,
      );
      expect(
        await targetContainer.read(followersCountProvider(targetId).future),
        0,
      );

      await targetContainer
          .read(followFlowControllerProvider.notifier)
          .approveIncomingRequest(senderId: requesterId);

      expect(
        await targetContainer.read(followingCountProvider(requesterId).future),
        1,
      );
      expect(
        await targetContainer.read(followersCountProvider(targetId).future),
        1,
      );
    });

    test('reject invalidates cached counts and refreshes to removed values', () async {
      await createApprovedEdge();
      await fs
          .collection('users')
          .doc(targetId)
          .collection('followRequests')
          .doc(requesterId)
          .set({
            'senderId': requesterId,
            'receiverId': targetId,
            'status': 'pending',
          });

      final targetContainer = containerFor(targetId);
      addTearDown(targetContainer.dispose);

      expect(
        await targetContainer.read(followingCountProvider(requesterId).future),
        1,
      );
      expect(
        await targetContainer.read(followersCountProvider(targetId).future),
        1,
      );

      await targetContainer
          .read(followFlowControllerProvider.notifier)
          .rejectIncomingRequest(senderId: requesterId);

      expect(
        await targetContainer.read(followingCountProvider(requesterId).future),
        0,
      );
      expect(
        await targetContainer.read(followersCountProvider(targetId).future),
        0,
      );
    });

    test('toggleRelationship unfollow refreshes stale cached counters', () async {
      await createApprovedEdge();

      final requesterContainer = containerFor(requesterId);
      addTearDown(requesterContainer.dispose);

      expect(
        await requesterContainer.read(followingCountProvider(requesterId).future),
        1,
      );
      expect(
        await requesterContainer.read(followersCountProvider(targetId).future),
        1,
      );

      await requesterContainer
          .read(followFlowControllerProvider.notifier)
          .toggleRelationship(
            targetUserId: targetId,
            targetIsPrivate: true,
            currentState: FollowState.approved,
          );

      expect(
        await requesterContainer.read(followingCountProvider(requesterId).future),
        0,
      );
      expect(
        await requesterContainer.read(followersCountProvider(targetId).future),
        0,
      );
    });
  });
}
