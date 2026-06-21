import 'dart:async';
import 'dart:developer' as developer show log;
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';

class BoomerangLikeResult {
  const BoomerangLikeResult({required this.liked, required this.likes});

  final bool liked;
  final int likes;
}

class BoomerangRepo {
  BoomerangRepo(this._fs);
  final FirebaseFirestore _fs;
  static final Set<String> _inFlightLikeWrites = <String>{};
  static const _logName = 'BoomerangRepo';

  /// Defensively reads a `createdAt`-style field into epoch milliseconds.
  ///
  /// Tolerates the several shapes the field has had across app versions and
  /// imports — [Timestamp], [DateTime], epoch [int]/[num], or ISO [String] —
  /// instead of a hard `as Timestamp` cast that throws on legacy documents
  /// and takes down the whole feed page. Returns `null` when the value is
  /// missing or unparseable (e.g. a pending server timestamp).
  static int? createdAtMillis(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final asInt = int.tryParse(value);
      if (asInt != null) return asInt;
      return DateTime.tryParse(value)?.millisecondsSinceEpoch;
    }
    return null;
  }

  static int _compareByCreatedAtDesc(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final aMs = createdAtMillis(a.data()['createdAt']);
    final bMs = createdAtMillis(b.data()['createdAt']);
    if (aMs == null && bMs == null) return 0;
    if (aMs == null) return 1;
    if (bMs == null) return -1;
    return bMs.compareTo(aMs);
  }

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
      chunks.add(
        idList.sublist(i, i + 30 > idList.length ? idList.length : i + 30),
      );
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
      allDocs.sort(_compareByCreatedAtDesc);
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

  /// Page of public boomerangs ordered by the server-computed `rankScore`
  /// field (preferred for Discovery / Home exploration). Cursor is the
  /// last score seen so the call stays stateless from the caller's
  /// perspective.
  ///
  /// Posts whose `rankScore` is missing are excluded from this query (the
  /// Firestore index requires the field to be set). Callers must fall
  /// back to [fetchPublicByCreatedAtPage] when this returns empty AND the
  /// dataset is fresh.
  Future<QuerySnapshot<Map<String, dynamic>>> fetchPublicByRankScorePage({
    double? startAfterScore,
    int limit = 20,
  }) async {
    Query<Map<String, dynamic>> q = _fs
        .collection('boomerangs')
        .where('ownerIsPrivate', isEqualTo: false)
        .orderBy('rankScore', descending: true)
        .limit(limit);
    if (startAfterScore != null) {
      q = q.where('rankScore', isLessThan: startAfterScore);
    }
    try {
      return await q.get();
    } catch (e, st) {
      developer.log(
        '[FEEDDBG] fetchPublicByRankScorePage FAILED startAfterScore='
        '$startAfterScore '
        '${e is FirebaseException ? 'code=${e.code} message=${e.message}' : 'type=${e.runtimeType}'}',
        name: _logName,
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Page of public boomerangs ordered by `createdAt`, with a millisecond
  /// cursor instead of a document snapshot so the cursor can live in pure
  /// domain types.
  Future<QuerySnapshot<Map<String, dynamic>>> fetchPublicByCreatedAtPage({
    int? startAfterMillis,
    int limit = 20,
  }) async {
    Query<Map<String, dynamic>> q = _fs
        .collection('boomerangs')
        .where('ownerIsPrivate', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(limit);
    if (startAfterMillis != null) {
      q = q.where(
        'createdAt',
        isLessThan: Timestamp.fromMillisecondsSinceEpoch(startAfterMillis),
      );
    }
    try {
      return await q.get();
    } catch (e, st) {
      developer.log(
        '[FEEDDBG] fetchPublicByCreatedAtPage FAILED startAfterMs='
        '$startAfterMillis '
        '${e is FirebaseException ? 'code=${e.code} message=${e.message}' : 'type=${e.runtimeType}'}',
        name: _logName,
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  /// Following-feed page using a millisecond cursor instead of a document
  /// snapshot.
  ///
  /// Permission-safe by construction. Firestore evaluates `canReadBoomerang`
  /// per returned document on list queries, so a single `whereIn` over all
  /// followed authors fails the WHOLE query with `permission-denied` if even
  /// one matched post is a private post the caller can't read (e.g. a private
  /// account whose reverse `followers/.../users/{me}` record is missing or
  /// stale). That used to break Home entirely for users following such
  /// accounts. To avoid it we never issue an unconstrained `whereIn`:
  ///
  ///  * Public posts by followed authors — constrained to
  ///    `ownerIsPrivate == false`, so every match is guaranteed readable.
  ///  * The caller's own posts — guaranteed readable (`userId == me`).
  ///  * Private posts by followed authors — best-effort: a `whereIn` per
  ///    chunk, and if that is denied (broken/stale follow record somewhere in
  ///    the chunk) we fall back to per-author queries and silently skip only
  ///    the authors we genuinely can't read, instead of failing the feed.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  fetchFollowingByCreatedAtPage({
    required Set<String> followingIds,
    required String myUid,
    int? startAfterMillis,
    int limit = 20,
  }) async {
    final followed =
        followingIds.where((u) => u.isNotEmpty && u != myUid).toList();

    Query<Map<String, dynamic>> ordered(Query<Map<String, dynamic>> q) {
      q = q.orderBy('createdAt', descending: true).limit(limit);
      if (startAfterMillis != null) {
        q = q.where(
          'createdAt',
          isLessThan: Timestamp.fromMillisecondsSinceEpoch(startAfterMillis),
        );
      }
      return q;
    }

    List<List<String>> chunked(List<String> ids) {
      final out = <List<String>>[];
      for (var i = 0; i < ids.length; i += 30) {
        out.add(ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30));
      }
      return out;
    }

    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    final col = _fs.collection('boomerangs');

    developer.log(
      '[FEEDDBG] fetchFollowingByCreatedAtPage followed=${followed.length} '
      'startAfterMs=$startAfterMillis limit=$limit',
      name: _logName,
    );

    // 1. Own posts (always readable).
    final ownSnap =
        await ordered(col.where('userId', isEqualTo: myUid)).get();
    for (final d in ownSnap.docs) {
      byId[d.id] = d;
    }

    // 2. Public posts by followed authors (always readable).
    for (final chunk in chunked(followed)) {
      final snap = await ordered(
        col
            .where('userId', whereIn: chunk)
            .where('ownerIsPrivate', isEqualTo: false),
      ).get();
      for (final d in snap.docs) {
        byId[d.id] = d;
      }
    }

    // 3. Private posts by followed authors (best-effort; never fatal).
    for (final chunk in chunked(followed)) {
      try {
        final snap = await ordered(
          col
              .where('userId', whereIn: chunk)
              .where('ownerIsPrivate', isEqualTo: true),
        ).get();
        for (final d in snap.docs) {
          byId[d.id] = d;
        }
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
        developer.log(
          '[FEEDDBG] private whereIn denied for chunk(size=${chunk.length}); '
          'falling back to per-author',
          name: _logName,
        );
        for (final author in chunk) {
          try {
            final snap = await ordered(
              col
                  .where('userId', isEqualTo: author)
                  .where('ownerIsPrivate', isEqualTo: true),
            ).get();
            for (final d in snap.docs) {
              byId[d.id] = d;
            }
          } on FirebaseException catch (e2) {
            if (e2.code != 'permission-denied') rethrow;
            // Broken/stale follow record for this private author — skip their
            // private posts rather than failing the whole feed.
            developer.log(
              '[FEEDDBG] skipping unreadable private author $author',
              name: _logName,
            );
          }
        }
      }
    }

    final allDocs = byId.values.toList();
    allDocs.sort(_compareByCreatedAtDesc);
    return allDocs.take(limit).toList();
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

  /// Paginated fetch for a specific user's posts.
  ///
  /// When [onlyPublic] is true the query is additionally constrained to
  /// `ownerIsPrivate == false`. This is REQUIRED whenever the caller is
  /// not the owner and is not a confirmed follower — Firestore's rules
  /// reject any list query that *might* return a private post the viewer
  /// can't read, so the constraint must be on the query itself, not
  /// applied after the fact. Without it, viewing a private user's
  /// profile races into a PERMISSION_DENIED error.
  Future<QuerySnapshot<Map<String, dynamic>>> fetchUserBoomerangsPage({
    required String userId,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 20,
    bool onlyPublic = false,
  }) {
    Query<Map<String, dynamic>> q = _fs
        .collection('boomerangs')
        .where('userId', isEqualTo: userId);
    if (onlyPublic) {
      q = q.where('ownerIsPrivate', isEqualTo: false);
    }
    q = q.orderBy('createdAt', descending: true).limit(limit);
    if (startAfter != null) {
      q = q.startAfterDocument(startAfter);
    }
    return q.get();
  }

  Future<BoomerangLikeResult?> setLike({
    required String boomerangId,
    required String userId,
    required bool shouldLike,
    String? actorName,
    String? actorAvatar,
  }) {
    return _writeLikeState(
      boomerangId: boomerangId,
      userId: userId,
      desiredLike: shouldLike,
      actorName: actorName,
      actorAvatar: actorAvatar,
    );
  }

  Future<BoomerangLikeResult?> toggleLike({
    required String boomerangId,
    required String userId,
    String? actorName,
    String? actorAvatar,
  }) {
    return _writeLikeState(
      boomerangId: boomerangId,
      userId: userId,
      desiredLike: null,
      actorName: actorName,
      actorAvatar: actorAvatar,
    );
  }

  Future<BoomerangLikeResult?> _writeLikeState({
    required String boomerangId,
    required String userId,
    required bool? desiredLike,
    String? actorName,
    String? actorAvatar,
  }) async {
    final inFlightKey = '$userId::$boomerangId';
    if (_inFlightLikeWrites.contains(inFlightKey)) {
      return null;
    }
    _inFlightLikeWrites.add(inFlightKey);
    final ref = _fs.collection('boomerangs').doc(boomerangId);
    String? ownerId;
    bool didChange = false;
    late BoomerangLikeResult result;
    var exists = false;

    try {
      await _fs.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return;
        exists = true;
        final data = snap.data() as Map<String, dynamic>;
        ownerId = data['userId'] as String?;

        final rawLikedBy = (data['likedBy'] as List?) ?? const <dynamic>[];
        final likedBySet = <String>{
          for (final uid in rawLikedBy)
            if (uid is String && uid.isNotEmpty) uid,
        };
        final wasLiked = likedBySet.contains(userId);
        final nextLiked = desiredLike ?? !wasLiked;
        didChange = wasLiked != nextLiked;

        if (nextLiked) {
          likedBySet.add(userId);
        } else {
          likedBySet.remove(userId);
        }

        final nextLikes = likedBySet.length;
        result = BoomerangLikeResult(
          liked: likedBySet.contains(userId),
          likes: nextLikes < 0 ? 0 : nextLikes,
        );

        tx.update(ref, {
          'likedBy': likedBySet.toList(growable: false),
          'likes': result.likes,
        });
      });

      if (!exists) return null;

      final likeRef = _fs
          .collection('users')
          .doc(userId)
          .collection('likes')
          .doc(boomerangId);
      if (result.liked) {
        await likeRef.set({'createdAt': FieldValue.serverTimestamp()});
      } else {
        await likeRef.delete().catchError((_) {});
      }

      if (ownerId != null && ownerId!.isNotEmpty && didChange) {
        await _fs.collection('users').doc(ownerId).update({
          'totalLikes': FieldValue.increment(result.liked ? 1 : -1),
        });
      }

      return result;
    } finally {
      _inFlightLikeWrites.remove(inFlightKey);
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
    bool ownerIsPrivate = false,
    int? videoWidth,
    int? videoHeight,
    double? videoAspectRatio,
    int? videoDurationMs,
  }) async {
    developer.log(
      'createBoomerangPost() start for user=$userId, hasCaption=${caption != null && caption.trim().isNotEmpty}, '
      'hashtags=${hashtags?.length ?? 0}',
      name: _logName,
    );
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
      } catch (e, st) {
        developer.log(
          'Non-fatal: hashtag pre-create batch failed',
          name: _logName,
          error: e,
          stackTrace: st,
        );
        // best effort; continue
      }
    }

    developer.log('Writing boomerang document to Firestore', name: _logName);
    final ref = await _fs.collection('boomerangs').add({
      'userId': userId,
      'userName': userName,
      'userAvatar': userAvatar,
      'videoUrl': videoUrl,
      'imageUrl': imageUrl,
      if (videoWidth != null) 'videoWidth': videoWidth,
      if (videoHeight != null) 'videoHeight': videoHeight,
      if (videoAspectRatio != null) 'videoAspectRatio': videoAspectRatio,
      if (videoDurationMs != null) 'videoDurationMs': videoDurationMs,
      if (caption != null) 'caption': caption,
      if (normalizedTags.isNotEmpty) 'hashtags': normalizedTags,
      'ownerIsPrivate': ownerIsPrivate,
      'likes': 0,
      'likedBy': <String>[],
      'commentsCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    developer.log('Boomerang document created: ${ref.id}', name: _logName);
    await _fs.collection('users').doc(userId).update({
      'boomerangsCount': FieldValue.increment(1),
    });
    developer.log(
      'User boomerangsCount incremented for user=$userId',
      name: _logName,
    );
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
      } catch (e, st) {
        developer.log(
          'Non-fatal: hashtag counter increment batch failed',
          name: _logName,
          error: e,
          stackTrace: st,
        );
        // ignore counter failure
      }
    }
    developer.log('createBoomerangPost() done: ${ref.id}', name: _logName);
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

    final followedList =
        followingIds.where((u) => u.isNotEmpty && u != currentUserId).toList();
    for (var i = 0; i < followedList.length; i += 30) {
      final end = i + 30 > followedList.length ? followedList.length : i + 30;
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
    final normalized =
        tags
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

    final followedList =
        followingIds
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
    final snap =
        await _fs
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
    final tags =
        (data?['hashtags'] as List?)?.cast<String>() ?? const <String>[];
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

  /// Fetches a shallow field snapshot for many boomerangs.
  /// Used by silent feed reconciliation to refresh likes/rank metadata
  /// without forcing a full feed reload.
  Future<Map<String, Map<String, dynamic>>> fetchBoomerangFieldsByIds(
    List<String> boomerangIds,
  ) async {
    final ids =
        boomerangIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const <String, Map<String, dynamic>>{};

    final out = <String, Map<String, dynamic>>{};
    for (var i = 0; i < ids.length; i += 30) {
      final end = i + 30 > ids.length ? ids.length : i + 30;
      final chunk = ids.sublist(i, end);
      final snap =
          await _fs
              .collection('boomerangs')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
      for (final doc in snap.docs) {
        final data = doc.data();
        out[doc.id] = <String, dynamic>{
          'likes': data['likes'],
          'likedBy': data['likedBy'],
          'rankScore': data['rankScore'],
        };
      }
    }
    return out;
  }
}
