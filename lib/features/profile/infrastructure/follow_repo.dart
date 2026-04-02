import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FollowRepo {
  FollowRepo(this._fs, this._auth);
  final FirebaseFirestore _fs;
  final FirebaseAuth _auth;

  String? get _uid => _auth.currentUser?.uid;

  String pickName(Map<String, dynamic> data) {
    final nickname = (data['nickname'] ?? data['username'] ?? '') as String;
    final fullName = (data['fullName'] ?? '') as String;
    if (nickname.trim().isNotEmpty) return nickname;
    if (fullName.trim().isNotEmpty) return fullName;
    return 'User';
  }

  String pickAvatar(Map<String, dynamic> data, String seed) {
    final avatar = (data['avatarUrl'] ?? '') as String;
    if (avatar.trim().isNotEmpty) return avatar;
    return '';
  }

  Stream<bool> watchIsFollowing(String targetUserId) {
    final me = _uid;
    if (me == null || me == targetUserId) {
      return const Stream<bool>.empty();
    }
    return _fs
        .collection('following')
        .doc(me)
        .collection('users')
        .doc(targetUserId)
        .snapshots()
        .map((d) => d.exists);
  }

  Stream<FollowRequest?> watchRequest({
    required String receiverId,
    required String senderId,
  }) {
    return _fs
        .collection('users')
        .doc(receiverId)
        .collection('followRequests')
        .doc(senderId)
        .snapshots()
        .map(
          (snap) => snap.exists
              ? FollowRequest.fromMap(snap.data()!, snap.id)
              : null,
        );
  }

  /// Start following a user or create a follow request if their profile is private.
  /// - Public: creates documents under following/{me}/users/{target} and followers/{target}/users/{me}.
  /// - Private: creates/keeps a pending follow request and a follow_request notification.
  Future<FollowOutcome> followOrRequest(String targetUserId) async {
    final me = _uid;
    if (me == null || me == targetUserId) return FollowOutcome.followed;

    final targetDoc = await _fs.collection('users').doc(targetUserId).get();
    final meDoc = await _fs.collection('users').doc(me).get();

    final targetData = targetDoc.data() ?? <String, dynamic>{};
    final meData = meDoc.data() ?? <String, dynamic>{};
    final isPrivate = (targetData['isPrivate'] ?? false) as bool;

    if (isPrivate) {
      final reqRef = _fs
          .collection('users')
          .doc(targetUserId)
          .collection('followRequests')
          .doc(me);
      await _fs.runTransaction((tx) async {
        final existing = await tx.get(reqRef);
        if (existing.exists) {
          return;
        }
        tx.set(reqRef, {
          'senderId': me,
          'receiverId': targetUserId,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
      // Push notification is handled server-side by Cloud Functions
      // (onFollowRequestCreated trigger).
      return FollowOutcome.requested;
    }

    final batch = _fs.batch();

    final followingRef = _fs
        .collection('following')
        .doc(me)
        .collection('users')
        .doc(targetUserId);
    batch.set(followingRef, {
      'userId': targetUserId,
      'userName': pickName(targetData),
      'userAvatar': targetData['avatarUrl'],
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final followersRef = _fs
        .collection('followers')
        .doc(targetUserId)
        .collection('users')
        .doc(me);
    batch.set(followersRef, {
      'userId': me,
      'userName': pickName(meData),
      'userAvatar': meData['avatarUrl'],
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.update(_fs.collection('users').doc(me), {
      'followingCount': FieldValue.increment(1),
    });
    batch.update(_fs.collection('users').doc(targetUserId), {
      'followersCount': FieldValue.increment(1),
    });

    await batch.commit();

    // Push notification is handled server-side by Cloud Functions
    // (onFollowerAdded trigger).
    return FollowOutcome.followed;
  }

  Future<void> follow(String targetUserId) async {
    await followOrRequest(targetUserId);
  }

  /// Accept a pending follow request (current user is receiver).
  Future<void> acceptRequest({
    required String senderId,
    String? notificationId,
  }) async {
    final receiver = _uid;
    if (receiver == null) return;

    final receiverDoc = await _fs.collection('users').doc(receiver).get();
    final senderDoc = await _fs.collection('users').doc(senderId).get();
    final receiverData = receiverDoc.data() ?? <String, dynamic>{};
    final senderData = senderDoc.data() ?? <String, dynamic>{};

    final requestRef = _fs
        .collection('users')
        .doc(receiver)
        .collection('followRequests')
        .doc(senderId);

    await _fs.runTransaction((tx) async {
      final reqSnap = await tx.get(requestRef);
      if (!reqSnap.exists) return;
      final req = reqSnap.data() ?? <String, dynamic>{};
      if ((req['status'] ?? 'pending') != 'pending') return;

      final followingRef = _fs
          .collection('following')
          .doc(senderId)
          .collection('users')
          .doc(receiver);
      final followerRef = _fs
          .collection('followers')
          .doc(receiver)
          .collection('users')
          .doc(senderId);

      tx.set(followingRef, {
        'userId': receiver,
        'userName': pickName(receiverData),
        'userAvatar': receiverData['avatarUrl'],
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      tx.set(followerRef, {
        'userId': senderId,
        'userName': pickName(senderData),
        'userAvatar': senderData['avatarUrl'],
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      tx.delete(requestRef);
    });

    if (notificationId != null) {
      final notifRef = _fs
          .collection('users')
          .doc(receiver)
          .collection('notifications')
          .doc(notificationId);
      await notifRef.set(
        {
          'read': true,
          // Flip to a standard follow notification so the client shows follow/unfollow.
          'type': 'follow',
        },
        SetOptions(merge: true),
      );
    }
  }

  /// Reject a pending follow request (current user is receiver).
  Future<void> rejectRequest({
    required String senderId,
    String? notificationId,
  }) async {
    final receiver = _uid;
    if (receiver == null) return;
    final requestRef = _fs
        .collection('users')
        .doc(receiver)
        .collection('followRequests')
        .doc(senderId);
    await requestRef.delete();
    if (notificationId != null) {
      final notifRef = _fs
          .collection('users')
          .doc(receiver)
          .collection('notifications')
          .doc(notificationId);
      await notifRef.delete();
    }
  }

  /// Stop following a user. Removes relationship documents.
  Future<void> unfollow(String targetUserId) async {
    final me = _uid;
    if (me == null || me == targetUserId) return;
    final batch = _fs.batch();
    final followingRef = _fs
        .collection('following')
        .doc(me)
        .collection('users')
        .doc(targetUserId);
    batch.delete(followingRef);
    final followersRef = _fs
        .collection('followers')
        .doc(targetUserId)
        .collection('users')
        .doc(me);
    batch.delete(followersRef);
    batch.update(_fs.collection('users').doc(me), {
      'followingCount': FieldValue.increment(-1),
    });
    batch.update(_fs.collection('users').doc(targetUserId), {
      'followersCount': FieldValue.increment(-1),
    });
    await batch.commit();
  }

  /// Whether current user follows target.
  Future<bool> isFollowing(String targetUserId) async {
    final me = _uid;
    if (me == null || me == targetUserId) return false;
    final doc =
        await _fs
            .collection('following')
            .doc(me)
            .collection('users')
            .doc(targetUserId)
            .get();
    return doc.exists;
  }

  /// Stream list of users current user follows.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchFollowing(String uid) {
    return _fs
        .collection('following')
        .doc(uid)
        .collection('users')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Stream list of users who follow the given user.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchFollowers(String uid) {
    return _fs
        .collection('followers')
        .doc(uid)
        .collection('users')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Auto-accept all pending requests when switching to public.
  Future<void> acceptAllPendingFor(String receiverId) async {
    final pending = await _fs
        .collection('users')
        .doc(receiverId)
        .collection('followRequests')
        .get();
    for (final doc in pending.docs) {
      final senderId = doc.id;
      await acceptRequest(senderId: senderId);
    }
  }
}

class FollowRequest {
  FollowRequest({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.status,
    required this.createdAt,
  });
  final String id;
  final String senderId;
  final String receiverId;
  final String status;
  final DateTime createdAt;

  bool get isPending => status == 'pending';

  factory FollowRequest.fromMap(Map<String, dynamic> data, String id) {
    final ts = data['createdAt'];
    final createdAt = ts is Timestamp ? ts.toDate() : DateTime.now();
    return FollowRequest(
      id: id,
      senderId: (data['senderId'] ?? '') as String,
      receiverId: (data['receiverId'] ?? '') as String,
      status: (data['status'] ?? 'pending') as String,
      createdAt: createdAt,
    );
  }
}

enum FollowOutcome { followed, requested }
