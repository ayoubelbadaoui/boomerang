import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

class BoomerangRepo {
  BoomerangRepo(this._fs);
  final FirebaseFirestore _fs;

  Future<void> addRandomBoomerang() async {
    // pick a random user
    final usersSnap = await _fs.collection('users').limit(50).get();
    if (usersSnap.docs.isEmpty) return;
    final docs = usersSnap.docs;
    final rand = Random();
    final userDoc = docs[rand.nextInt(docs.length)];
    final user = userDoc.data();
    final uid = userDoc.id;

    // simple random video and image placeholder urls
    final samples = [
      // Google sample videos (support range requests and iOS playback)
      'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
      'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
      'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
    ];
    final videoUrl = samples[rand.nextInt(samples.length)];
    final posters = [
      'https://picsum.photos/seed/bmg1/1200/1600',
      'https://picsum.photos/seed/bmg2/1200/1600',
      'https://picsum.photos/seed/bmg3/1200/1600',
      'https://picsum.photos/seed/bmg4/1200/1600',
      'https://picsum.photos/seed/bmg5/1200/1600',
    ];
    final imageUrl = posters[rand.nextInt(posters.length)];

    await _fs.collection('boomerangs').add({
      'userId': uid,
      'userName': user['fullName'] ?? user['nickname'] ?? 'User',
      'userAvatar': user['avatarUrl'],
      'videoUrl': videoUrl,
      'imageUrl': imageUrl,
      'likes': rand.nextInt(1000),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchBoomerangs() {
    return _fs
        .collection('boomerangs')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> toggleLike({
    required String boomerangId,
    required String userId,
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

  Future<String> createBoomerangPost({
    required String userId,
    required String userName,
    String? userAvatar,
    required String videoUrl,
    String? imageUrl,
  }) async {
    final ref = await _fs.collection('boomerangs').add({
      'userId': userId,
      'userName': userName,
      'userAvatar': userAvatar,
      'videoUrl': videoUrl,
      'imageUrl': imageUrl,
      'likes': 0,
      'likedBy': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }
}
