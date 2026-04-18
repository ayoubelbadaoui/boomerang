import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:boomerang/features/moderation/domain/moderation_repo.dart';
import 'package:boomerang/features/moderation/domain/report_entity.dart';

class FirestoreModerationRepo implements ModerationRepo {
  FirestoreModerationRepo(this._fs);
  final FirebaseFirestore _fs;

  CollectionReference<Map<String, dynamic>> get _reports =>
      _fs.collection('reports');

  CollectionReference<Map<String, dynamic>> _blockedUsers(String uid) =>
      _fs.collection('users').doc(uid).collection('blocked_users');

  @override
  Future<void> submitReport(ReportEntity report) async {
    await _reports.add(report.toMap());
  }

  @override
  Future<void> blockUser({
    required String blockerUid,
    required String blockedUid,
    String? blockedName,
    String? blockedAvatar,
  }) async {
    // Check which follow edges exist so we can decrement counts accurately.
    final blockerFollowsBlocked = (await _fs
            .collection('following')
            .doc(blockerUid)
            .collection('users')
            .doc(blockedUid)
            .get())
        .exists;
    final blockedFollowsBlocker = (await _fs
            .collection('following')
            .doc(blockedUid)
            .collection('users')
            .doc(blockerUid)
            .get())
        .exists;

    final batch = _fs.batch();

    // 1. Add to blocked list
    batch.set(_blockedUsers(blockerUid).doc(blockedUid), {
      'blockedUid': blockedUid,
      if (blockedName != null) 'blockedName': blockedName,
      if (blockedAvatar != null) 'blockedAvatar': blockedAvatar,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 2. Remove follow: blocker -> blocked
    batch.delete(
      _fs.collection('following').doc(blockerUid).collection('users').doc(blockedUid),
    );
    batch.delete(
      _fs.collection('followers').doc(blockedUid).collection('users').doc(blockerUid),
    );

    // 3. Remove follow: blocked -> blocker
    batch.delete(
      _fs.collection('following').doc(blockedUid).collection('users').doc(blockerUid),
    );
    batch.delete(
      _fs.collection('followers').doc(blockerUid).collection('users').doc(blockedUid),
    );

    // 4. Remove pending follow requests in both directions
    batch.delete(
      _fs.collection('users').doc(blockerUid).collection('followRequests').doc(blockedUid),
    );
    batch.delete(
      _fs.collection('users').doc(blockedUid).collection('followRequests').doc(blockerUid),
    );

    // 5. Decrement counts for each edge that actually existed
    if (blockerFollowsBlocked) {
      batch.update(_fs.collection('users').doc(blockerUid), {
        'followingCount': FieldValue.increment(-1),
      });
      batch.update(_fs.collection('users').doc(blockedUid), {
        'followersCount': FieldValue.increment(-1),
      });
    }
    if (blockedFollowsBlocker) {
      batch.update(_fs.collection('users').doc(blockedUid), {
        'followingCount': FieldValue.increment(-1),
      });
      batch.update(_fs.collection('users').doc(blockerUid), {
        'followersCount': FieldValue.increment(-1),
      });
    }

    await batch.commit();
  }

  @override
  Future<void> unblockUser({
    required String blockerUid,
    required String blockedUid,
  }) async {
    await _blockedUsers(blockerUid).doc(blockedUid).delete();
  }

  @override
  Stream<List<String>> watchBlockedUsers(String uid) {
    return _blockedUsers(uid).snapshots().map(
          (snap) => snap.docs.map((d) => d.id).toList(),
        );
  }

  @override
  Future<bool> isBlocked({
    required String checkerUid,
    required String targetUid,
  }) async {
    final doc = await _blockedUsers(checkerUid).doc(targetUid).get();
    return doc.exists;
  }
}
