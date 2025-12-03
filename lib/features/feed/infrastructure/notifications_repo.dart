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
        _fs.collection('notifications').doc(toUserId).collection('items').doc();
    await ref.set({
      'type': 'follow',
      'actorUserId': actorUserId,
      'actorName': actorName,
      'actorAvatar': actorAvatar,
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
        _fs.collection('notifications').doc(toUserId).collection('items').doc();
    await ref.set({
      'type': 'like',
      'boomerangId': boomerangId,
      'boomerangImage': boomerangImage,
      'actorUserId': actorUserId,
      'actorName': actorName,
      'actorAvatar': actorAvatar,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watch(String uid) {
    return _fs
        .collection('notifications')
        .doc(uid)
        .collection('items')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }
}


