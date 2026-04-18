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
      var created = false;
      await _fs.runTransaction((tx) async {
        final existing = await tx.get(reqRef);
        if (existing.exists) {
          final data = existing.data() ?? <String, dynamic>{};
          // Honour a 24-hour cooldown after rejection.
          if (data['status'] == 'rejected') {
            final rejTs = data['rejectedAt'];
            if (rejTs is Timestamp) {
              final elapsed =
                  DateTime.now().difference(rejTs.toDate()).inHours;
              if (elapsed < 24) return;
            }
          } else {
            return;
          }
        }
        tx.set(reqRef, {
          'senderId': me,
          'receiverId': targetUserId,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
        created = true;
      });
      if (!created) return FollowOutcome.requested;
      return FollowOutcome.requested;
    }

    final followingRef = _fs
        .collection('following')
        .doc(me)
        .collection('users')
        .doc(targetUserId);
    final followersRef = _fs
        .collection('followers')
        .doc(targetUserId)
        .collection('users')
        .doc(me);

    await _fs.runTransaction((tx) async {
      final existingEdge = await tx.get(followingRef);
      if (existingEdge.exists) return;

      tx.set(followingRef, {
        'userId': targetUserId,
        'userName': pickName(targetData),
        'userAvatar': targetData['avatarUrl'],
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      tx.set(followersRef, {
        'userId': me,
        'userName': pickName(meData),
        'userAvatar': meData['avatarUrl'],
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      tx.update(_fs.collection('users').doc(me), {
        'followingCount': FieldValue.increment(1),
      });
      tx.update(_fs.collection('users').doc(targetUserId), {
        'followersCount': FieldValue.increment(1),
      });
    });

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

      tx.update(_fs.collection('users').doc(senderId), {
        'followingCount': FieldValue.increment(1),
      });
      tx.update(_fs.collection('users').doc(receiver), {
        'followersCount': FieldValue.increment(1),
      });

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
          'type': 'follow',
        },
        SetOptions(merge: true),
      );
    } else {
      // Find and merge the matching follow_request notification so the inbox
      // doesn't show stale accept/reject buttons.
      final notifQuery = await _fs
          .collection('users')
          .doc(receiver)
          .collection('notifications')
          .where('type', isEqualTo: 'follow_request')
          .where('senderId', isEqualTo: senderId)
          .limit(1)
          .get();
      for (final doc in notifQuery.docs) {
        await doc.reference.set(
          {'read': true, 'type': 'follow'},
          SetOptions(merge: true),
        );
      }
    }
  }

  /// Reject a pending follow request (current user is receiver).
  /// Writes a rejected status with a timestamp so the sender is subject to a
  /// 24-hour cooldown before they can re-request.
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
    await requestRef.set({
      'status': 'rejected',
      'rejectedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (notificationId != null) {
      final notifRef = _fs
          .collection('users')
          .doc(receiver)
          .collection('notifications')
          .doc(notificationId);
      await notifRef.delete();
    }
  }

  /// Cancel an outgoing pending follow request (current user is sender).
  Future<void> cancelRequest(String targetUserId) async {
    final me = _uid;
    if (me == null) return;
    await _fs
        .collection('users')
        .doc(targetUserId)
        .collection('followRequests')
        .doc(me)
        .delete();
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
  /// Rejected requests are cleaned up, not accepted.
  Future<void> acceptAllPendingFor(String receiverId) async {
    final requests = await _fs
        .collection('users')
        .doc(receiverId)
        .collection('followRequests')
        .get();
    for (final doc in requests.docs) {
      final data = doc.data();
      final status = (data['status'] ?? 'pending') as String;
      if (status == 'pending') {
        await acceptRequest(senderId: doc.id);
      } else {
        await doc.reference.delete();
      }
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
