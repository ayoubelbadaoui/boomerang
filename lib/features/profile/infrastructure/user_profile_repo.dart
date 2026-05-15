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
  CollectionReference<Map<String, dynamic>> get _loginAliases =>
      _firestore.collection('login_usernames');

  Set<String> _aliasesFromData(Map<String, dynamic>? data) {
    if (data == null) return const <String>{};
    final values = <String>{
      (data['nicknameLower'] ?? '').toString().trim().toLowerCase(),
      (data['usernameLower'] ?? '').toString().trim().toLowerCase(),
    };
    values.removeWhere((alias) => alias.isEmpty);
    return values;
  }

  Future<void> _syncLoginAliases({
    required String uid,
    required String email,
    required Set<String> aliases,
    Set<String> previousAliases = const <String>{},
  }) async {
    final safeEmail = email.trim();
    if (safeEmail.isEmpty || aliases.isEmpty) return;
    final safeAliases = aliases
        .map((a) => a.trim().toLowerCase())
        .where((a) => a.isNotEmpty)
        .toSet();
    if (safeAliases.isEmpty) return;

    final batch = _firestore.batch();
    for (final alias in safeAliases) {
      batch.set(_loginAliases.doc(alias), {
        'uid': uid,
        'email': safeEmail,
        'alias': alias,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    for (final oldAlias in previousAliases) {
      if (!safeAliases.contains(oldAlias)) {
        batch.delete(_loginAliases.doc(oldAlias));
      }
    }
    await batch.commit();
  }

  Future<bool> _isAliasAvailable({
    required String uid,
    required String alias,
  }) async {
    final doc = await _loginAliases.doc(alias).get();
    if (!doc.exists) return true;
    final owner = doc.data()?['uid']?.toString().trim() ?? '';
    return owner.isEmpty || owner == uid;
  }

  /// Public availability check for the username/nickname edit flow.
  /// Returns true when the (sanitized) candidate is either unclaimed
  /// or already owned by the current user — matching the rule used by
  /// signup's live check, so the UI is consistent across surfaces.
  Future<bool> isUsernameAvailable(String candidate) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('No authenticated user');
    final sanitized = _sanitizeNicknameForRules(candidate, uid);
    return _isAliasAvailable(uid: uid, alias: sanitized);
  }

  Future<void> _ensureAliasesAvailable({
    required String uid,
    required Set<String> aliases,
  }) async {
    for (final alias in aliases) {
      final available = await _isAliasAvailable(uid: uid, alias: alias);
      if (!available) {
        throw StateError('Username "$alias" is already taken. Please choose another one.');
      }
    }
  }

  Future<String> _pickAvailableAlias({
    required String uid,
    required String preferred,
  }) async {
    var candidate = _sanitizeNicknameForRules(preferred, uid);
    if (await _isAliasAvailable(uid: uid, alias: candidate)) {
      return candidate;
    }

    final uidTail = uid.substring(0, uid.length >= 4 ? 4 : uid.length);
    for (var i = 1; i <= 100; i++) {
      final suffix = i == 1 ? uidTail : '$uidTail$i';
      final maxBaseLen = 20 - (suffix.length + 1);
      final end = maxBaseLen.clamp(3, candidate.length).toInt();
      final base = candidate.substring(0, end);
      final retry = _sanitizeNicknameForRules('${base}_$suffix', uid);
      if (await _isAliasAvailable(uid: uid, alias: retry)) {
        return retry;
      }
    }
    throw StateError('Could not allocate an available username. Please try another nickname.');
  }

  Future<void> upsertCurrentUserProfile({
    required String gender,
    required DateTime birthday,
    required String fullName,
    required String nickname,
    required String email,
    String? avatarUrl,
    /// Stored as Firestore `isPrivate`. Defaults to public (`false`) when omitted.
    bool isPrivate = false,
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
      final existingData = Map<String, dynamic>.from(existing.data() ?? {});
      final previousAliases = _aliasesFromData(existingData);
      final Map<String, dynamic> data = Map<String, dynamic>.from(existingData);
      data['gender'] = gender;
      data['birthday'] = birthday.toIso8601String();
      data['isPrivate'] = isPrivate;
      data['fullName'] = safeFullName;
      data['fullNameLower'] = fullNameLower;
      data['email'] = email;
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

      await _ensureAliasesAvailable(
        uid: uid,
        aliases: _aliasesFromData(data),
      );
      await ref.set(data, SetOptions(merge: true));
      await _syncLoginAliases(
        uid: uid,
        email: email,
        aliases: _aliasesFromData(data),
        previousAliases: previousAliases,
      );
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
    nickname = await _pickAvailableAlias(uid: user.uid, preferred: nickname);

    try {
      await _firestore.collection('users').doc(user.uid).set({
        'fullName': displayName,
        'nickname': nickname,
        'fullNameLower': displayName.toLowerCase(),
        'nicknameLower': nickname,
        'email': email,
        if (user.photoURL != null) 'avatarUrl': user.photoURL,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _syncLoginAliases(
        uid: user.uid,
        email: email,
        aliases: <String>{nickname},
      );
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
    bool? phoneVerified,
    String? bio,
    DateTime? birthday,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('No authenticated user');
    Map<String, dynamic>? existingData;
    String? sanitizedNickname;
    if (nickname != null || email != null) {
      final existing = await _firestore.collection('users').doc(uid).get();
      existingData = existing.data();
    }
    final Map<String, dynamic> data = {
      if (fullName != null) 'fullName': fullName,
      if (fullName != null) 'fullNameLower': fullName.toLowerCase(),
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (email != null) 'email': email.trim(),
      if (phone != null) 'phone': phone,
      if (phoneVerified != null) 'phoneVerified': phoneVerified,
      if (bio != null) 'bio': bio,
      if (birthday != null) 'birthday': birthday.toIso8601String(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (nickname != null) {
      sanitizedNickname = _sanitizeNicknameForRules(nickname, uid);
      await _ensureAliasesAvailable(
        uid: uid,
        aliases: {sanitizedNickname},
      );
      data['nickname'] = sanitizedNickname;
      data['nicknameLower'] = sanitizedNickname;
    }
    if (data.length == 1) return; // only updatedAt, nothing to do
    await _firestore
        .collection('users')
        .doc(uid)
        .set(data, SetOptions(merge: true));

    if (existingData != null) {
      final previousAliases = _aliasesFromData(existingData);
      final nextAliases = _aliasesFromData({
        ...existingData,
        if (sanitizedNickname != null) 'nicknameLower': sanitizedNickname,
      });
      final effectiveEmail =
          (data['email'] ?? existingData['email'] ?? '').toString().trim();
      await _syncLoginAliases(
        uid: uid,
        email: effectiveEmail,
        aliases: nextAliases,
        previousAliases: previousAliases,
      );
    }
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
      final profile = await _firestore.collection('users').doc(uid).get();
      final aliases = _aliasesFromData(profile.data());
      final batch = _firestore.batch();
      for (final alias in aliases) {
        batch.delete(_loginAliases.doc(alias));
      }
      await batch.commit();

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
