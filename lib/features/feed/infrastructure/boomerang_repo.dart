import 'dart:async';
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
      'ownerIsPrivate': (user['isPrivate'] ?? false) as bool,
      'likes': rand.nextInt(1000),
      'commentsCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<QuerySnapshot<Map<String, dynamic>>> fetchBoomerangsPage({
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 20,
  }) {
    Query<Map<String, dynamic>> q = _fs
        .collection('boomerangs')
        .where('ownerIsPrivate', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(limit);
    if (startAfter != null) {
      q = q.startAfterDocument(startAfter);
    }
    return q.get();
  }

  /// Paginated fetch for the home feed: only boomerangs by the given userIds.
  /// Firestore `whereIn` supports up to 30 values, so we batch if needed
  /// and merge results sorted by createdAt descending.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchFollowingFeedPage({
    required Set<String> followingIds,
    required String myUid,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 20,
  }) async {
    final allIds = {...followingIds, myUid};
    if (allIds.isEmpty) return [];

    final chunks = <List<String>>[];
    final idList = allIds.toList();
    for (var i = 0; i < idList.length; i += 30) {
      chunks.add(idList.sublist(i, i + 30 > idList.length ? idList.length : i + 30));
    }

    final allDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final chunk in chunks) {
      Query<Map<String, dynamic>> q = _fs
          .collection('boomerangs')
          .where('userId', whereIn: chunk)
          .orderBy('createdAt', descending: true)
          .limit(limit);
      if (startAfter != null) {
        q = q.startAfterDocument(startAfter);
      }
      final snap = await q.get();
      allDocs.addAll(snap.docs);
    }

    if (chunks.length > 1) {
      allDocs.sort((a, b) {
        final aT = a.data()['createdAt'] as Timestamp?;
        final bT = b.data()['createdAt'] as Timestamp?;
        if (aT == null && bT == null) return 0;
        if (aT == null) return 1;
        if (bT == null) return -1;
        return bT.compareTo(aT);
      });
    }

    return allDocs.take(limit).toList();
  }

  /// Paginated fetch for discover: only public boomerangs.
  Future<QuerySnapshot<Map<String, dynamic>>> fetchPublicBoomerangsPage({
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 20,
  }) {
    Query<Map<String, dynamic>> q = _fs
        .collection('boomerangs')
        .where('ownerIsPrivate', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(limit);
    if (startAfter != null) {
      q = q.startAfterDocument(startAfter);
    }
    return q.get();
  }

  /// Stream for discover: only public boomerangs.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchPublicBoomerangs() {
    return _fs
        .collection('boomerangs')
        .where('ownerIsPrivate', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
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
    final ref = _fs.collection('boomerangs').doc(boomerangId);
    String? ownerId;
    bool? wasLiked;
    await _fs.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      ownerId = data['userId'] as String?;
      final List likedBy = (data['likedBy'] as List?) ?? <String>[];
      wasLiked = likedBy.contains(userId);
      tx.update(ref, {
        'likedBy':
            wasLiked!
                ? FieldValue.arrayRemove([userId])
                : FieldValue.arrayUnion([userId]),
        'likes': FieldValue.increment(wasLiked! ? -1 : 1),
      });
    });
    if (wasLiked != null) {
      final likeRef = _fs.collection('users').doc(userId).collection('likes').doc(boomerangId);
      if (wasLiked!) {
        await likeRef.delete();
      } else {
        await likeRef.set({'createdAt': FieldValue.serverTimestamp()});
      }
    }
    if (ownerId != null && ownerId!.isNotEmpty && wasLiked != null) {
      await _fs.collection('users').doc(ownerId).update({
        'totalLikes': FieldValue.increment(wasLiked! ? -1 : 1),
      });
    }
    // Push notification is handled server-side by Cloud Functions
    // (onBoomerangLikeUpdated trigger).
  }

  Future<String> createBoomerangPost({
    required String userId,
    required String userName,
    String? userAvatar,
    required String videoUrl,
    String? imageUrl,
    String? caption,
    List<String>? hashtags,
    bool ownerIsPrivate = false,
  }) async {
    // Normalize hashtags: lowercase, strip leading '#', drop empties
    final normalizedTags =
        (hashtags ?? const <String>[])
            .map((t) => t.trim().toLowerCase().replaceFirst(RegExp('^#'), ''))
            .where((t) => t.isNotEmpty)
            .toList();

    // Ensure hashtag docs exist before creating the post (for discover search)
    if (normalizedTags.isNotEmpty) {
      final preBatch = _fs.batch();
      for (final tag in normalizedTags.toSet()) {
        final doc = _fs.collection('hashtags').doc(tag);
        preBatch.set(doc, {
          'updatedAt': FieldValue.serverTimestamp(),
          'count': FieldValue.increment(0),
        }, SetOptions(merge: true));
      }
      try {
        await preBatch.commit();
      } catch (_) {
        // best effort; continue
      }
    }

    final ref = await _fs.collection('boomerangs').add({
      'userId': userId,
      'userName': userName,
      'userAvatar': userAvatar,
      'videoUrl': videoUrl,
      'imageUrl': imageUrl,
      if (caption != null) 'caption': caption,
      if (normalizedTags.isNotEmpty) 'hashtags': normalizedTags,
      'ownerIsPrivate': ownerIsPrivate,
      'likes': 0,
      'likedBy': <String>[],
      'commentsCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _fs.collection('users').doc(userId).update({
      'boomerangsCount': FieldValue.increment(1),
    });
    // Increment hashtags usage counters (best-effort)
    if (normalizedTags.isNotEmpty) {
      final batch = _fs.batch();
      for (final tag in normalizedTags.toSet()) {
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

  /// Streams boomerangs tagged with [tag].
  ///
  /// Merges three Firestore queries (deduped by doc id):
  ///  * Public posts (`ownerIsPrivate == false`).
  ///  * The current user's own posts (so private accounts still discover
  ///    their own content).
  ///  * Posts authored by accounts in [followingIds] — chunked into
  ///    `whereIn` groups of 30. This is what lets a follower see a private
  ///    account's tagged posts without exposing them to non-followers.
  ///    Security rules independently enforce the same gate via
  ///    `canReadBoomerang`, so non-followers can't read these even if the
  ///    UID list is tampered with.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchByHashtag(
    String tag, {
    String? currentUserId,
    Set<String> followingIds = const <String>{},
  }) {
    final normalized = tag.toLowerCase();
    final col = _fs.collection('boomerangs');

    final substreams = <Stream<QuerySnapshot<Map<String, dynamic>>>>[
      col
          .where('hashtags', arrayContains: normalized)
          .where('ownerIsPrivate', isEqualTo: false)
          .limit(100)
          .snapshots(),
    ];

    if (currentUserId != null && currentUserId.isNotEmpty) {
      substreams.add(
        col
            .where('hashtags', arrayContains: normalized)
            .where('userId', isEqualTo: currentUserId)
            .limit(100)
            .snapshots(),
      );
    }

    final followedList = followingIds
        .where((u) => u.isNotEmpty && u != currentUserId)
        .toList();
    for (var i = 0; i < followedList.length; i += 30) {
      final end =
          i + 30 > followedList.length ? followedList.length : i + 30;
      final chunk = followedList.sublist(i, end);
      substreams.add(
        col
            .where('hashtags', arrayContains: normalized)
            .where('userId', whereIn: chunk)
            .limit(100)
            .snapshots(),
      );
    }

    return _combineSnapshotStreams(substreams);
  }

  /// Like [watchByHashtag] but matches *any* of [tags] using
  /// `arrayContainsAny` (Firestore caps this operator at 30 values, so the
  /// caller is responsible for bounding the list). Used for substring
  /// hashtag search where the query expands to a set of candidate tags.
  ///
  /// Followed accounts are queried one-by-one because Firestore disallows
  /// combining `arrayContainsAny` with `whereIn` in the same query. To keep
  /// the subscription count bounded we cap the followed-author scan at
  /// [followedScanLimit] users.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> watchByHashtagsAny(
    List<String> tags, {
    String? currentUserId,
    Set<String> followingIds = const <String>{},
    int followedScanLimit = 50,
  }) {
    final normalized = tags
        .map((t) => t.toLowerCase())
        .where((t) => t.isNotEmpty)
        .toSet()
        .take(30)
        .toList();
    if (normalized.isEmpty) {
      return Stream.value(const []);
    }

    final col = _fs.collection('boomerangs');
    final substreams = <Stream<QuerySnapshot<Map<String, dynamic>>>>[
      col
          .where('hashtags', arrayContainsAny: normalized)
          .where('ownerIsPrivate', isEqualTo: false)
          .limit(100)
          .snapshots(),
    ];

    if (currentUserId != null && currentUserId.isNotEmpty) {
      substreams.add(
        col
            .where('hashtags', arrayContainsAny: normalized)
            .where('userId', isEqualTo: currentUserId)
            .limit(100)
            .snapshots(),
      );
    }

    final followedList = followingIds
        .where((u) => u.isNotEmpty && u != currentUserId)
        .take(followedScanLimit)
        .toList();
    for (final uid in followedList) {
      substreams.add(
        col
            .where('hashtags', arrayContainsAny: normalized)
            .where('userId', isEqualTo: uid)
            .limit(50)
            .snapshots(),
      );
    }

    return _combineSnapshotStreams(substreams);
  }

  /// Combines N Firestore snapshot streams into a single deduped doc list.
  /// Emits once every input stream has produced its first snapshot, then on
  /// every subsequent change. Order of returned docs is unspecified —
  /// callers should sort by `createdAt` if ordering matters.
  static Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _combineSnapshotStreams(
    List<Stream<QuerySnapshot<Map<String, dynamic>>>> streams,
  ) {
    if (streams.isEmpty) return Stream.value(const []);
    if (streams.length == 1) return streams.first.map((s) => s.docs);

    late StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
        controller;
    final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    final latest = List<QuerySnapshot<Map<String, dynamic>>?>.filled(
      streams.length,
      null,
    );
    var doneCount = 0;

    void emit() {
      if (latest.any((v) => v == null)) return;
      final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final snap in latest) {
        for (final d in snap!.docs) {
          byId[d.id] = d;
        }
      }
      controller.add(byId.values.toList());
    }

    controller =
        StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      onListen: () {
        for (var i = 0; i < streams.length; i++) {
          final idx = i;
          subs.add(
            streams[idx].listen(
              (v) {
                latest[idx] = v;
                emit();
              },
              onError: controller.addError,
              onDone: () {
                doneCount++;
                if (doneCount == streams.length) controller.close();
              },
            ),
          );
        }
      },
      onCancel: () async {
        for (final s in subs) {
          await s.cancel();
        }
      },
    );
    return controller.stream;
  }

  /// Synchronise the denormalised `ownerIsPrivate` flag on every boomerang
  /// owned by [uid]. Run after the user toggles their account privacy so the
  /// discover/hashtag queries (which filter server-side on this flag) stay
  /// truthful even for posts created before the toggle.
  Future<void> syncOwnerPrivacy({
    required String uid,
    required bool isPrivate,
  }) async {
    final snap = await _fs
        .collection('boomerangs')
        .where('userId', isEqualTo: uid)
        .get();
    if (snap.docs.isEmpty) return;

    var batch = _fs.batch();
    var pending = 0;
    for (final doc in snap.docs) {
      final current = doc.data()['ownerIsPrivate'];
      if (current is bool && current == isPrivate) continue;
      batch.update(doc.reference, {'ownerIsPrivate': isPrivate});
      pending++;
      if (pending >= 400) {
        await batch.commit();
        batch = _fs.batch();
        pending = 0;
      }
    }
    if (pending > 0) await batch.commit();
  }

  /// Deletes a boomerang and adjusts denormalized counters (best-effort).
  Future<void> deleteBoomerang({
    required String boomerangId,
    required String userId,
  }) async {
    final docRef = _fs.collection('boomerangs').doc(boomerangId);
    final snap = await docRef.get();
    final data = snap.data();

    await docRef.delete();

    // Decrement user's boomerangsCount
    await _fs.collection('users').doc(userId).update({
      'boomerangsCount': FieldValue.increment(-1),
    });

    // Decrement hashtag counters (best-effort, mirrors createBoomerangPost)
    final tags = (data?['hashtags'] as List?)?.cast<String>() ?? const <String>[];
    if (tags.isNotEmpty) {
      final batch = _fs.batch();
      for (final tag in tags.toSet()) {
        final doc = _fs.collection('hashtags').doc(tag);
        batch.set(doc, {
          'count': FieldValue.increment(-1),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      try {
        await batch.commit();
      } catch (_) {}
    }
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
