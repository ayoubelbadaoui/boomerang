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

  Future<QuerySnapshot<Map<String, dynamic>>> fetchBoomerangsOnce() {
    return _fs
        .collection('boomerangs')
        .orderBy('createdAt', descending: true)
        .get();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> fetchBoomerangsPage({
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 20,
  }) {
    Query<Map<String, dynamic>> q = _fs
        .collection('boomerangs')
        .orderBy('createdAt', descending: true)
        .limit(limit);
    if (startAfter != null) {
      q = q.startAfterDocument(startAfter);
    }
    return q.get();
  }

  /// Paginated fetch for a specific user's posts
  Future<QuerySnapshot<Map<String, dynamic>>> fetchUserBoomerangsPage({
    required String userId,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 20,
  }) {
    Query<Map<String, dynamic>> q = _fs
        .collection('boomerangs')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit);
    if (startAfter != null) {
      q = q.startAfterDocument(startAfter);
    }
    return q.get();
  }

  Future<void> toggleLike({
    required String boomerangId,
    required String userId,
    String? actorName,
    String? actorAvatar,
  }) async {
    String _avatar(String? url, String seed) =>
        (url != null && url.isNotEmpty)
            ? url
            : 'https://picsum.photos/seed/$seed/200/200';
    final ref = _fs.collection('boomerangs').doc(boomerangId);
    bool addedLike = false;
    Map<String, dynamic>? boomerangData;
    await _fs.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      boomerangData = data;
      final List likedBy = (data['likedBy'] as List?) ?? <String>[];
      final bool isLiked = likedBy.contains(userId);
      tx.update(ref, {
        'likedBy':
            isLiked
                ? FieldValue.arrayRemove([userId])
                : FieldValue.arrayUnion([userId]),
        'likes': FieldValue.increment(isLiked ? -1 : 1),
      });
      if (!isLiked) {
        addedLike = true;
      }
    });
    // Add notification outside transaction on like add
    if (addedLike && boomerangData != null) {
      final ownerId = (boomerangData!['userId'] ?? '') as String;
      if (ownerId.isNotEmpty && ownerId != userId) {
        await _fs
            .collection('users')
            .doc(ownerId)
            .collection('notifications')
            .add({
              'type': 'like',
              'boomerangId': boomerangId,
              'boomerangImage': boomerangData!['imageUrl'],
              'senderId': userId,
              'actorName': actorName,
              'actorAvatar': _avatar(actorAvatar, userId),
              'read': false,
              'createdAt': FieldValue.serverTimestamp(),
            });
      }
    }
  }

  Future<String> createBoomerangPost({
    required String userId,
    required String userName,
    String? userAvatar,
    required String videoUrl,
    String? imageUrl,
    String? caption,
    List<String>? hashtags,
  }) async {
    final ref = await _fs.collection('boomerangs').add({
      'userId': userId,
      'userName': userName,
      'userAvatar': userAvatar,
      'videoUrl': videoUrl,
      'imageUrl': imageUrl,
      if (caption != null) 'caption': caption,
      if (hashtags != null) 'hashtags': hashtags,
      'likes': 0,
      'likedBy': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
    // Increment hashtags usage counters (best-effort)
    if (hashtags != null && hashtags.isNotEmpty) {
      final batch = _fs.batch();
      for (final tag in hashtags.toSet()) {
        final doc = _fs.collection('hashtags').doc(tag);
        batch.set(doc, {
          'count': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      try {
        await batch.commit();
      } catch (_) {
        // ignore counter failure
      }
    }
    return ref.id;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchByHashtag(String tag) {
    final normalized = tag.toLowerCase();
    // Avoid composite index requirement by not ordering; client can sort if needed.
    return _fs
        .collection('boomerangs')
        .where('hashtags', arrayContains: normalized)
        .limit(100)
        .snapshots();
  }

  /// Fetch a single boomerang document by id.
  /// Returns null if not found.
  Future<(String, Map<String, dynamic>)?> fetchBoomerangById(
    String boomerangId,
  ) async {
    final snap = await _fs.collection('boomerangs').doc(boomerangId).get();
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return (snap.id, data);
  }
}
