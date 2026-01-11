import 'package:cloud_firestore/cloud_firestore.dart';

class LikesRepo {
  LikesRepo(this._fs);
  final FirebaseFirestore _fs;

  /// Toggle like using a transaction to keep counts and likedBy in sync.
  Future<void> toggleLike({
    required String boomerangId,
    required String userId,
    String? actorName,
    String? actorAvatar,
  }) async {
    final ref = _fs.collection('boomerangs').doc(boomerangId);
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
