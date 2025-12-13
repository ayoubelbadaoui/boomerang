import 'package:cloud_firestore/cloud_firestore.dart';

class SavedRepo {
  SavedRepo(this._fs);
  final FirebaseFirestore _fs;

  CollectionReference<Map<String, dynamic>> _col(String userId) =>
      _fs.collection('users').doc(userId).collection('saved');

  Stream<bool> watchIsSaved({
    required String userId,
    required String boomerangId,
  }) {
    return _col(userId).doc(boomerangId).snapshots().map((s) => s.exists);
  }

  Future<bool> isSaved({
    required String userId,
    required String boomerangId,
  }) async {
    final doc = await _col(userId).doc(boomerangId).get();
    return doc.exists;
  }

  Future<void> toggleSave({
    required String userId,
    required String boomerangId,
    required Map<String, dynamic> boomerangData,
  }) async {
    final ref = _col(userId).doc(boomerangId);
    final snap = await ref.get();
    if (snap.exists) {
      await ref.delete();
      return;
    }
    // Store minimal snapshot for fast rendering
    final data = <String, dynamic>{
      'boomerangId': boomerangId,
      'userId': boomerangData['userId'],
      'userName': boomerangData['userName'],
      'userAvatar': boomerangData['userAvatar'],
      'imageUrl': boomerangData['imageUrl'],
      'videoUrl': boomerangData['videoUrl'],
      'caption': boomerangData['caption'],
      'hashtags': boomerangData['hashtags'],
      'savedAt': FieldValue.serverTimestamp(),
    };
    await ref.set(data);
  }

  Future<void> remove({required String userId, required String boomerangId}) {
    return _col(userId).doc(boomerangId).delete();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchSaved(String userId) {
    return _col(userId).orderBy('savedAt', descending: true).snapshots();
  }
}
