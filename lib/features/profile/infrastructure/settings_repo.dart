import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../domain/app_settings.dart';

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
    return _doc().snapshots().map((e) => AppSettings.fromMap(e.data()));
  }

  Future<void> update(Map<String, dynamic> data) async {
    await _doc().set(data, SetOptions(merge: true));
  }
}








