import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
    required String address,
    String? avatarUrl,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('No authenticated user');
    await _firestore.collection('users').doc(uid).set({
      'gender': gender,
      'birthday': birthday.toIso8601String(),
      'fullName': fullName,
      'nickname': nickname,
      'email': email,
      'phone': phone,
      'address': address,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> uploadAvatar(File file) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('No authenticated user');
    final ref = _storage.ref().child('users/$uid/avatar.jpg');
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
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
    final nickname =
        displayName.isNotEmpty
            ? displayName
            : (email.isNotEmpty
                ? email.split('@').first
                : 'user_${user.uid.substring(0, 6)}');

    await _firestore.collection('users').doc(user.uid).set({
      'fullName': displayName,
      'nickname': nickname,
      'email': email,
      if (user.photoURL != null) 'avatarUrl': user.photoURL,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Partially update current user's profile fields.
  Future<void> updateCurrentUserProfile({
    String? fullName,
    String? nickname,
    String? avatarUrl,
    String? phone,
    String? address,
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
      if (nickname != null) 'nickname': nickname,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (phone != null) 'phone': phone,
      if (address != null) 'address': address,
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
