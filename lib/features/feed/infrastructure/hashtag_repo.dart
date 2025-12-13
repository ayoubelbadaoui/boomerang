import 'package:cloud_firestore/cloud_firestore.dart';

class HashtagRepo {
  HashtagRepo(this._fs);
  final FirebaseFirestore _fs;

  Future<QuerySnapshot<Map<String, dynamic>>> searchPrefixPage({
    required String prefix,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 30,
  }) {
    final String end = '$prefix\uf8ff';
    Query<Map<String, dynamic>> q = _fs
        .collection('hashtags')
        .orderBy(FieldPath.documentId)
        .startAt([prefix])
        .endAt([end])
        .limit(limit);
    if (startAfter != null) {
      q = q.startAfterDocument(startAfter);
    }
    return q.get();
  }
}
