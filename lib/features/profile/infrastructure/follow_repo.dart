import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FollowRepo {
  FollowRepo(this._fs, this._auth);
  final FirebaseFirestore _fs;
  final FirebaseAuth _auth;

  String? get _uid => _auth.currentUser?.uid;

  /// Start following a user. Creates documents under:
  /// - following/{me}/users/{target}
  /// - followers/{target}/users/{me}
  Future<void> follow(String targetUserId) async {
    final me = _uid;
    if (me == null || me == targetUserId) return;

    final targetDoc = await _fs.collection('users').doc(targetUserId).get();
    final meDoc = await _fs.collection('users').doc(me).get();

    final targetData = targetDoc.data() ?? <String, dynamic>{};
    final meData = meDoc.data() ?? <String, dynamic>{};

    final batch = _fs.batch();

    final followingRef =
        _fs.collection('following').doc(me).collection('users').doc(targetUserId);
    batch.set(followingRef, {
      'userId': targetUserId,
      'userName':
          (targetData['nickname']?.toString().isNotEmpty == true
              ? targetData['nickname']
              : targetData['fullName']) ??
          'User',
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
      'userName':
          (meData['nickname']?.toString().isNotEmpty == true
              ? meData['nickname']
              : meData['fullName']) ??
          'User',
      'userAvatar': meData['avatarUrl'],
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();
  }

  /// Stop following a user. Removes relationship documents.
  Future<void> unfollow(String targetUserId) async {
    final me = _uid;
    if (me == null || me == targetUserId) return;
    final batch = _fs.batch();
    final followingRef =
        _fs.collection('following').doc(me).collection('users').doc(targetUserId);
    batch.delete(followingRef);
    final followersRef = _fs
        .collection('followers')
        .doc(targetUserId)
        .collection('users')
        .doc(me);
    batch.delete(followersRef);
    await batch.commit();
  }

  /// Whether current user follows target.
  Future<bool> isFollowing(String targetUserId) async {
    final me = _uid;
    if (me == null || me == targetUserId) return false;
    final doc = await _fs
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
}


