import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../domain/app_settings.dart';

class SettingsRepoException implements Exception {
  const SettingsRepoException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SettingsRepo {
  SettingsRepo(this._fs, this._auth);
  final FirebaseFirestore _fs;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> _doc() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('No authenticated user');
    }
    return _fs.collection('users').doc(uid).collection('meta').doc('settings');
  }

  Future<AppSettings> fetch() async {
    final d = await _doc().get();
    return AppSettings.fromMap(d.data());
  }

  Stream<AppSettings> watch() {
    return _doc()
        .snapshots()
        .map((e) => AppSettings.fromMap(e.data()))
        .handleError((e, st) {});
  }

  Future<void> update(Map<String, dynamic> data) async {
    await _doc().set(data, SetOptions(merge: true));
  }

  Future<void> updatePrivacy({required bool isPrivate}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const SettingsRepoException('You need to be signed in.');
    }

    try {
      final settingsDoc = _doc();
      final profileDoc = _fs.collection('users').doc(uid);
      final batch = _fs.batch();

      // Keep settings and profile privacy in sync in one commit.
      batch.set(settingsDoc, {
        'privateAccount': isPrivate,
      }, SetOptions(merge: true));
      batch.set(profileDoc, {'isPrivate': isPrivate}, SetOptions(merge: true));

      await batch.commit().timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const SettingsRepoException(
        'Network timeout while updating privacy. Please try again.',
      );
    } on FirebaseException catch (e) {
      throw SettingsRepoException(_mapFirebaseError(e));
    } catch (_) {
      throw const SettingsRepoException(
        'Could not update privacy right now. Please try again.',
      );
    }
  }

  String _mapFirebaseError(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'You do not have permission to change privacy settings.';
      case 'unavailable':
        return 'Service is temporarily unavailable. Please try again.';
      case 'deadline-exceeded':
        return 'Request timed out while updating privacy.';
      case 'unauthenticated':
        return 'Your session expired. Please sign in again.';
      default:
        return 'Could not update privacy right now. Please try again.';
    }
  }
}
