import 'package:boomerang/features/profile/infrastructure/follow_repo.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('private follow lifecycle integration', () {
    late FakeFirebaseFirestore fs;
    late FollowRepo requesterRepo;
    late FollowRepo targetRepo;

    const requesterId = 'requester_uid';
    const targetId = 'private_target_uid';
    const thirdId = 'third_user_uid';

    Future<void> seedUsers() async {
      await fs.collection('users').doc(requesterId).set({
        'nickname': 'Requester',
        'fullName': 'Requester User',
        'avatarUrl': '',
        'isPrivate': false,
        'followersCount': 0,
        'followingCount': 0,
      });
      await fs.collection('users').doc(targetId).set({
        'nickname': 'Target',
        'fullName': 'Private Target',
        'avatarUrl': '',
        'isPrivate': true,
        'followersCount': 0,
        'followingCount': 0,
      });
      await fs.collection('users').doc(thirdId).set({
        'nickname': 'Third',
        'fullName': 'Third User',
        'avatarUrl': '',
        'isPrivate': false,
        'followersCount': 0,
        'followingCount': 0,
      });
    }

    FollowRepo buildRepoFor(String uid) {
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: uid, email: '$uid@example.com'),
        signedIn: true,
      );
      return FollowRepo(fs, auth);
    }

    Future<int> followersCount(String uid) async {
      final doc = await fs.collection('users').doc(uid).get();
      return (doc.data()?['followersCount'] ?? 0) as int;
    }

    Future<int> followingCount(String uid) async {
      final doc = await fs.collection('users').doc(uid).get();
      return (doc.data()?['followingCount'] ?? 0) as int;
    }

    Future<DocumentSnapshot<Map<String, dynamic>>> requestDoc() {
      return fs
          .collection('users')
          .doc(targetId)
          .collection('followRequests')
          .doc(requesterId)
          .get();
    }

    Future<DocumentSnapshot<Map<String, dynamic>>> followingEdge() {
      return fs
          .collection('following')
          .doc(requesterId)
          .collection('users')
          .doc(targetId)
          .get();
    }

    Future<DocumentSnapshot<Map<String, dynamic>>> followerEdge() {
      return fs
          .collection('followers')
          .doc(targetId)
          .collection('users')
          .doc(requesterId)
          .get();
    }

    setUp(() async {
      fs = FakeFirebaseFirestore();
      await seedUsers();
      requesterRepo = buildRepoFor(requesterId);
      targetRepo = buildRepoFor(targetId);
    });

    test('request then approve grants follow access immediately', () async {
      final outcome = await requesterRepo.followOrRequest(targetId);
      expect(outcome, FollowOutcome.requested);

      final pending = await requestDoc();
      expect(pending.exists, isTrue);
      expect(pending.data()?['status'], 'pending');

      await targetRepo.acceptRequest(senderId: requesterId);

      expect((await requestDoc()).exists, isFalse);
      expect((await followingEdge()).exists, isTrue);
      expect((await followerEdge()).exists, isTrue);
      expect(await requesterRepo.isFollowing(targetId), isTrue);
      expect(await followingCount(requesterId), 1);
      expect(await followersCount(targetId), 1);
    });

    test('request then reject removes request and denies follow access', () async {
      final outcome = await requesterRepo.followOrRequest(targetId);
      expect(outcome, FollowOutcome.requested);
      expect((await requestDoc()).exists, isTrue);

      await targetRepo.rejectRequest(senderId: requesterId);

      expect((await requestDoc()).exists, isFalse);
      expect((await followingEdge()).exists, isFalse);
      expect((await followerEdge()).exists, isFalse);
      expect(await requesterRepo.isFollowing(targetId), isFalse);
      expect(await followingCount(requesterId), 0);
      expect(await followersCount(targetId), 0);
    });

    test('repeat taps and retries are idempotent', () async {
      await requesterRepo.followOrRequest(targetId);
      await requesterRepo.followOrRequest(targetId);

      final requests = await fs
          .collection('users')
          .doc(targetId)
          .collection('followRequests')
          .where('senderId', isEqualTo: requesterId)
          .get();
      expect(requests.docs.length, 1);

      await targetRepo.acceptRequest(senderId: requesterId);
      await targetRepo.acceptRequest(senderId: requesterId);

      expect(await followingCount(requesterId), 1);
      expect(await followersCount(targetId), 1);
      expect((await followingEdge()).exists, isTrue);
      expect((await followerEdge()).exists, isTrue);

      await requesterRepo.unfollow(targetId);
      await requesterRepo.unfollow(targetId);

      expect((await followingEdge()).exists, isFalse);
      expect((await followerEdge()).exists, isFalse);
      expect(await followingCount(requesterId), 0);
      expect(await followersCount(targetId), 0);
    });

    test('approve/reject race leaves canonical converged result', () async {
      await requesterRepo.followOrRequest(targetId);
      expect((await requestDoc()).exists, isTrue);

      await Future.wait([
        targetRepo.acceptRequest(senderId: requesterId),
        targetRepo.rejectRequest(senderId: requesterId),
      ]);

      final reqExists = (await requestDoc()).exists;
      final followingExists = (await followingEdge()).exists;
      final followerExists = (await followerEdge()).exists;
      final requesterFollowing = await followingCount(requesterId);
      final targetFollowers = await followersCount(targetId);

      expect(reqExists, isFalse);
      expect(followingExists, followerExists);
      if (followingExists) {
        expect(requesterFollowing, 1);
        expect(targetFollowers, 1);
      } else {
        expect(requesterFollowing, 0);
        expect(targetFollowers, 0);
      }
    });
  });
}
