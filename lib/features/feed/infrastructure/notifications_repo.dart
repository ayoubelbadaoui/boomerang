import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationsRepo {
  NotificationsRepo(this._fs);
  final FirebaseFirestore _fs;

  Future<void> addFollow({
    required String toUserId,
    required String actorUserId,
    required String actorName,
    String? actorAvatar,
  }) async {
    final ref =
        _fs.collection('users').doc(toUserId).collection('notifications').doc();
    await ref.set({
      'type': 'follow',
      'senderId': actorUserId,
      'actorName': actorName,
      'actorAvatar': actorAvatar,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addFollowRequest({
    required String toUserId,
    required String actorUserId,
    required String actorName,
    String? actorAvatar,
  }) async {
    final ref =
        _fs.collection('users').doc(toUserId).collection('notifications').doc();
    await ref.set({
      'type': 'follow_request',
      'senderId': actorUserId,
      'actorName': actorName,
      'actorAvatar': actorAvatar,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addLike({
    required String toUserId,
    required String boomerangId,
    required String actorUserId,
    required String actorName,
    String? actorAvatar,
    String? boomerangImage,
  }) async {
    final ref =
        _fs.collection('users').doc(toUserId).collection('notifications').doc();
    await ref.set({
      'type': 'like',
      'boomerangId': boomerangId,
      'boomerangImage': boomerangImage,
      'senderId': actorUserId,
      'actorName': actorName,
      'actorAvatar': actorAvatar,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watch(String uid) {
    return _fs
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Stream unread count using server-side filtering.
  Stream<int> watchUnreadCount(String uid) {
    return _fs
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.size);
  }

  /// Mark a single notification as read (idempotent).
  Future<void> markRead({required String uid, required String notificationId}) {
    final canonical =
        _fs.collection('notifications').doc(uid).collection('items').doc(notificationId);
    final legacy =
        _fs.collection('users').doc(uid).collection('notifications').doc(notificationId);

    Future<void> updateDoc(DocumentReference<Map<String, dynamic>> ref) async {
      await _fs.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return;
        final data = snap.data() as Map<String, dynamic>;
        if (data['read'] == true) return;
        tx.update(ref, {'read': true, 'readAt': FieldValue.serverTimestamp()});
      }).catchError((_) {
        // ignore if legacy doc missing
      });
    }

    return Future.wait([updateDoc(canonical), updateDoc(legacy)]);
  }
}




