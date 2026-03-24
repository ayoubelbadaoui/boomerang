import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:developer' as developer;
import 'dart:io';

class UserProfileRepo {
  UserProfileRepo(this._firestore, this._auth, this._storage);
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  Future<void> upsertCurrentUserProfile({
    required String gender,
    required DateTime birthday,
    required String fullName,
    required String nickname,
    required String email,
    required String phone,
    String? avatarUrl,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('No authenticated user');
    final safeFullName = fullName.trim();
    final rawNickname = nickname.trim().isNotEmpty ? nickname.trim() : safeFullName;
    final fullNameLower = safeFullName.toLowerCase();
    // Firestore rules require nickname/nicknameLower: 3–20 chars, [a-z0-9._] only.
    // Build merged doc from existing + our data so merged result always passes rules.
    final ref = _firestore.collection('users').doc(uid);
    try {
      final existing = await ref.get();
      final Map<String, dynamic> data = Map<String, dynamic>.from(existing.data() ?? {});
      data['gender'] = gender;
      data['birthday'] = birthday.toIso8601String();
      data['fullName'] = safeFullName;
      data['fullNameLower'] = fullNameLower;
      data['email'] = email;
      data['phone'] = phone;
      if (avatarUrl != null) data['avatarUrl'] = avatarUrl;
      data['updatedAt'] = FieldValue.serverTimestamp();
      data['createdAt'] = data['createdAt'] ?? FieldValue.serverTimestamp();

      final sanitizedNick = _sanitizeNicknameForRules(rawNickname, uid);
      data['nickname'] = sanitizedNick;
      data['nicknameLower'] = sanitizedNick;

      if (data.containsKey('username') || data.containsKey('usernameLower')) {
        final existingUser = data['username'] as String?;
        if (existingUser != null && existingUser.isNotEmpty) {
          final sanitized = _sanitizeNicknameForRules(existingUser, uid);
          data['username'] = sanitized;
          data['usernameLower'] = sanitized;
        } else {
          data.remove('username');
          data.remove('usernameLower');
        }
      }

      await ref.set(data, SetOptions(merge: true));
    } catch (e, stackTrace) {
      developer.log(
        'UserProfileRepo.upsertCurrentUserProfile failed (users/$uid)',
        name: 'UserProfileRepo',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Sanitize nickname to satisfy Firestore rules: 3–20 chars, [a-z0-9._] only.
  static String _sanitizeNicknameForRules(String raw, String uid) {
    if (raw.isEmpty) return 'user_${uid.substring(0, uid.length >= 6 ? 6 : uid.length)}';
    var s = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._]'), '_');
    if (s.length < 3) s = 'user_${uid.substring(0, uid.length >= 6 ? 6 : uid.length)}';
    if (s.length > 20) s = s.substring(0, 20);
    return s;
  }

  Future<String> uploadAvatar(File file) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('No authenticated user');
    final ref = _storage.ref().child('users/$uid/avatar.jpg');
    try {
      await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      return ref.getDownloadURL();
    } catch (e, stackTrace) {
      developer.log(
        'UserProfileRepo.uploadAvatar failed (users/$uid/avatar.jpg)',
        name: 'UserProfileRepo',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Ensure a minimal user profile document exists for the current user.
  /// This will only create the document if it does not already exist.
  Future<void> ensureBasicProfileIfMissing() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (doc.exists) return;

    final displayName = user.displayName ?? '';
    final email = user.email ?? '';
    var nickname =
        displayName.isNotEmpty
            ? displayName
            : (email.isNotEmpty
                ? email.split('@').first
                : 'user_${user.uid.substring(0, 6)}');
    // Firestore rules require nickname 3–20 chars, [a-z0-9._]; ensure minimum length.
    if (nickname.length < 3) nickname = 'user_${user.uid.substring(0, 6)}';
    nickname = nickname.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._]'), '_');
    if (nickname.length < 3) nickname = 'user_${user.uid.substring(0, 6)}';
    if (nickname.length > 20) nickname = nickname.substring(0, 20);

    try {
      await _firestore.collection('users').doc(user.uid).set({
        'fullName': displayName,
        'nickname': nickname,
        'fullNameLower': displayName.toLowerCase(),
        'nicknameLower': nickname,
        'email': email,
        if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty)
          'phone': user.phoneNumber,
        if (user.photoURL != null) 'avatarUrl': user.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e, stackTrace) {
      developer.log(
        'UserProfileRepo.ensureBasicProfileIfMissing failed (users/${user.uid})',
        name: 'UserProfileRepo',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Partially update current user's profile fields.
  Future<void> updateCurrentUserProfile({
    String? fullName,
    String? nickname,
    String? avatarUrl,
    String? email,
    String? phone,
    String? bio,
    String? instagram,
    String? facebook,
    String? twitter,
    DateTime? birthday,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('No authenticated user');
    final Map<String, dynamic> data = {
      if (fullName != null) 'fullName': fullName,
      if (fullName != null) 'fullNameLower': fullName.toLowerCase(),
      if (nickname != null) 'nickname': nickname,
      if (nickname != null) 'nicknameLower': nickname.toLowerCase(),
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (bio != null) 'bio': bio,
      if (instagram != null) 'instagram': instagram,
      if (facebook != null) 'facebook': facebook,
      if (twitter != null) 'twitter': twitter,
      if (birthday != null) 'birthday': birthday.toIso8601String(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (data.length == 1) return; // only updatedAt, nothing to do
    await _firestore
        .collection('users')
        .doc(uid)
        .set(data, SetOptions(merge: true));
  }

  Future<void> deleteAccount() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      // Delete user-created boomerangs
      final booms =
          await _firestore
              .collection('boomerangs')
              .where('userId', isEqualTo: uid)
              .get();
      for (final d in booms.docs) {
        try {
          await _firestore.collection('boomerangs').doc(d.id).delete();
        } catch (_) {}
      }
      // Delete user settings/meta
      try {
        await _firestore
            .collection('users')
            .doc(uid)
            .collection('meta')
            .doc('settings')
            .delete();
      } catch (_) {}
      // Delete user profile document
      await _firestore.collection('users').doc(uid).delete();
    } catch (_) {
      // ignore
    }
    try {
      await _auth.currentUser?.delete();
    } catch (_) {
      // Firebase might require re-auth; leave to UI to handle
    }
    try {
      await _auth.signOut();
    } catch (_) {
      // ignore
    }
  }
}
