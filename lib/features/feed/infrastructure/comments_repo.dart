import 'package:cloud_firestore/cloud_firestore.dart';

class CommentsRepo {
  CommentsRepo(this._fs);
  final FirebaseFirestore _fs;

  Stream<QuerySnapshot<Map<String, dynamic>>> watch(String boomerangId) {
    return _fs
        .collection('boomerangs')
        .doc(boomerangId)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> add({
    required String boomerangId,
    required String userId,
    required String userName,
    String? userAvatar,
    required String text,
  }) async {
    String _avatar(String? url, String seed) =>
        (url != null && url.isNotEmpty)
            ? url
            : 'https://picsum.photos/seed/$seed/200/200';
    await _fs
        .collection('boomerangs')
        .doc(boomerangId)
        .collection('comments')
        .add({
          'userId': userId,
          'userName': userName,
          'userAvatar': userAvatar,
          'text': text,
          'createdAt': FieldValue.serverTimestamp(),
          'likes': 0,
          'likedBy': <String>[],
        });
    // Notify owner of the boomerang about the new comment
    try {
      final postSnap = await _fs.collection('boomerangs').doc(boomerangId).get();
      if (!postSnap.exists) return;
      final data = postSnap.data() as Map<String, dynamic>;
      final ownerId = (data['userId'] ?? '') as String;
      if (ownerId.isEmpty || ownerId == userId) return;
      await _fs
          .collection('users')
          .doc(ownerId)
          .collection('notifications')
          .add({
            'type': 'comment',
            'boomerangId': boomerangId,
            'boomerangImage': data['imageUrl'],
            'senderId': userId,
            'actorName': userName,
          'actorAvatar': _avatar(userAvatar, userId),
            'text': text,
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
    } catch (_) {
      // ignore notification failure
    }
  }

  Future<void> addReply({
    required String boomerangId,
    required String parentCommentId,
    required String userId,
    required String userName,
    String? userAvatar,
    required String text,
  }) async {
    String _avatar(String? url, String seed) =>
        (url != null && url.isNotEmpty)
            ? url
            : 'https://picsum.photos/seed/$seed/200/200';
    await _fs
        .collection('boomerangs')
        .doc(boomerangId)
        .collection('comments')
        .doc(parentCommentId)
        .collection('replies')
        .add({
          'userId': userId,
          'userName': userName,
          'userAvatar': userAvatar,
          'text': text,
          'createdAt': FieldValue.serverTimestamp(),
          'likes': 0,
          'likedBy': <String>[],
        });
    // Best-effort notify post owner as well.
    try {
      final postSnap = await _fs.collection('boomerangs').doc(boomerangId).get();
      if (!postSnap.exists) return;
      final data = postSnap.data() as Map<String, dynamic>;
      final ownerId = (data['userId'] ?? '') as String;
      if (ownerId.isEmpty || ownerId == userId) return;
      await _fs
          .collection('users')
          .doc(ownerId)
          .collection('notifications')
          .add({
            'type': 'comment',
            'boomerangId': boomerangId,
            'boomerangImage': data['imageUrl'],
            'senderId': userId,
            'actorName': userName,
            'actorAvatar': _avatar(userAvatar, userId),
            'text': text,
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
    } catch (_) {
      // ignore notification failure
    }
  }

  Future<void> toggleLike({
    required String boomerangId,
    required String commentId,
    required String userId,
  }) async {
    final ref = _fs
        .collection('boomerangs')
        .doc(boomerangId)
        .collection('comments')
        .doc(commentId);
    await _fs.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      final List likedBy = (data['likedBy'] as List?) ?? <String>[];
      final bool isLiked = likedBy.contains(userId);
      tx.update(ref, {
        'likedBy':
            isLiked
                ? FieldValue.arrayRemove([userId])
                : FieldValue.arrayUnion([userId]),
        'likes': FieldValue.increment(isLiked ? -1 : 1),
      });
    });
  }
}
