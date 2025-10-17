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
}
