import 'package:cloud_firestore/cloud_firestore.dart';

class UserSearchRepo {
  UserSearchRepo(this._fs);
  final FirebaseFirestore _fs;

  /// Prefix search by nicknameLower and fullNameLower; merges and returns unique docs
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> searchUsers(
    String query, {
    int limit = 20,
  }) async {
    final q = query.toLowerCase();
    final end = '$q\uf8ff';
    final nick =
        await _fs
            .collection('users')
            .orderBy('nicknameLower')
            .startAt([q])
            .endAt([end])
            .limit(limit)
            .get();
    final full =
        await _fs
            .collection('users')
            .orderBy('fullNameLower')
            .startAt([q])
            .endAt([end])
            .limit(limit)
            .get();
    final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> map = {};
    for (final d in [...nick.docs, ...full.docs]) {
      map[d.id] = d;
    }
    return map.values.toList();
  }
}



