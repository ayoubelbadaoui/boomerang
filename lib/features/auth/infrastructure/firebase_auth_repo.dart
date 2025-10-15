import 'package:boomerang/features/auth/infrastructure/auth_repo.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../domain/auth_user.dart';

class FirebaseAuthRepo implements AuthRepo {
  FirebaseAuthRepo(this._auth);
  final FirebaseAuth _auth;

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

  @override
  Future<AuthUser> signIn(String email, String password) async {
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
  Future<AuthUser> signUp(
    String email,
    String password,
    String name,
    String birthday,
  ) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final u = cred.user!;
    return AuthUser(
      uid: u.uid,
      email: u.email,
      name: name,
      birthday: DateTime.parse(birthday),
    );
  }

  @override
  Future<void> signOut() => _auth.signOut();
}
