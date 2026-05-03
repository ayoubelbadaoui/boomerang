import 'package:cloud_firestore/cloud_firestore.dart';

class HashtagRepo {
  HashtagRepo(this._fs);
  final FirebaseFirestore _fs;

  /// Streams the most popular hashtags (capped at [limit]). Used as the
  /// candidate pool for client-side substring search since Firestore has
  /// no native LIKE/contains operator.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchTop({int limit = 2000}) {
    return _fs
        .collection('hashtags')
        .orderBy('count', descending: true)
        .limit(limit)
        .snapshots();
  }
}
