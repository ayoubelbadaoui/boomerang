import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Handles username claiming; writes onto the user doc (no mapping collection).
class UsernameRepo {
  UsernameRepo(this._fs, this._auth);
  final FirebaseFirestore _fs;
  final FirebaseAuth _auth;

  /// Claim a username by writing it onto the user doc. No separate mapping collection.
  Future<void> claimUsername(String rawUsername) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated user');
    }
    final username = rawUsername.trim();
    final usernameLower = username.toLowerCase();
    if (username.isEmpty) {
      throw StateError('Username required');
    }
    final displayName = (user.displayName ?? '').trim();
    // Enforce required fields: fullName/nickname set to username when missing.
    final fullName = displayName.isNotEmpty ? displayName : username;
    final nickname = username;
    final userRef = _fs.collection('users').doc(user.uid);

    await userRef.set(
      {
        'username': username,
        'usernameLower': usernameLower,
        'nickname': nickname,
        'nicknameLower': nickname.toLowerCase(),
        'fullName': fullName,
        'fullNameLower': fullName.toLowerCase(),
        'email': user.email,
              'isPrivate': false, // default to public on first write
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
