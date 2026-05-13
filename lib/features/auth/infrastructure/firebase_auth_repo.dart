import 'package:boomerang/features/auth/infrastructure/auth_repo.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../domain/auth_user.dart';

class FirebaseAuthRepo implements AuthRepo {
  FirebaseAuthRepo(this._auth, this._firestore);
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  @override
  AuthUser? get currentUser {
    final u = _auth.currentUser;
    if (u == null) return null;
    return AuthUser(
      uid: u.uid,
      email: u.email,
      name: u.displayName,
      birthday: u.metadata.creationTime ?? DateTime.now(),
    );
  }

  @override
  Stream<AuthUser?> watch() => _auth.authStateChanges().map(
    (u) =>
        u == null
            ? null
            : AuthUser(
              uid: u.uid,
              email: u.email,
              name: u.displayName,
              birthday: u.metadata.creationTime ?? DateTime.now(),
            ),
  );

  bool _looksLikeEmail(String value) => value.contains('@');

  Future<String> _resolveEmailForSignIn(String identifier) async {
    final input = identifier.trim();
    if (input.isEmpty) {
      throw FirebaseAuthException(code: 'invalid-email');
    }
    if (_looksLikeEmail(input)) return input;

    final normalized = input.toLowerCase();
    final aliasDoc =
        await _firestore.collection('login_usernames').doc(normalized).get();
    if (aliasDoc.exists) {
      final email = aliasDoc.data()?['email']?.toString().trim() ?? '';
      if (email.isNotEmpty) return email;
    }

    throw FirebaseAuthException(code: 'user-not-found');
  }

  @override
  Future<AuthUser> signIn(String emailOrUsername, String password) async {
    final email = await _resolveEmailForSignIn(emailOrUsername);
    final cred = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final u = cred.user!;
    return AuthUser(
      uid: u.uid,
      email: u.email,
      name: u.displayName,
      birthday: u.metadata.creationTime ?? DateTime.now(),
    );
  }

  @override
  Future<AuthUser> signUp(String email, String password, String name) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final u = cred.user!;
    return AuthUser(
      uid: u.uid,
      email: u.email,
      name: name,
      birthday: DateTime.now(),
    );
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }
}
