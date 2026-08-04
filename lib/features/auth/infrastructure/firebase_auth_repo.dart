import 'dart:developer' as dev;

import 'package:boomerang/core/utils/auth_debug_log.dart';
import 'package:boomerang/core/utils/perf_log.dart';
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
      dev.log('resolveEmail: empty identifier', name: 'Auth');
      throw FirebaseAuthException(code: 'invalid-email');
    }
    if (_looksLikeEmail(input)) {
      dev.log('resolveEmail: using email directly', name: 'Auth');
      return input;
    }

    final normalized = input.toLowerCase();
    dev.log('resolveEmail: looking up username=$normalized', name: 'Auth');
    try {
      final aliasDoc = await PerfLog.track(
        'signIn.usernameLookup',
        () => _firestore.collection('login_usernames').doc(normalized).get(),
      );
      if (aliasDoc.exists) {
        final email = aliasDoc.data()?['email']?.toString().trim() ?? '';
        if (email.isNotEmpty) {
          dev.log('resolveEmail: username mapped to $email', name: 'Auth');
          return email;
        }
        dev.log(
          'resolveEmail: username doc exists but email field is empty',
          name: 'Auth',
        );
      } else {
        dev.log('resolveEmail: no login_usernames doc for $normalized', name: 'Auth');
      }
    } catch (e, st) {
      AuthDebugLog.authFailed(
        flow: 'signIn',
        error: e,
        stackTrace: st,
        identifier: input,
        step: 'username_lookup',
      );
      rethrow;
    }

    throw FirebaseAuthException(code: 'user-not-found');
  }

  @override
  Future<AuthUser> signIn(String emailOrUsername, String password) async {
    final identifier = emailOrUsername.trim();
    AuthDebugLog.logFirebaseContext();
    dev.log(
      'signIn START identifier=$identifier passwordLen=${password.length}',
      name: 'Auth',
    );

    String email;
    try {
      email = await _resolveEmailForSignIn(emailOrUsername);
    } catch (e, st) {
      AuthDebugLog.authFailed(
        flow: 'signIn',
        error: e,
        stackTrace: st,
        identifier: identifier,
        step: 'resolve_email',
      );
      rethrow;
    }

    try {
      final cred = await PerfLog.track(
        'signIn.firebaseAuth',
        () => _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        ),
      );
      final u = cred.user!;
      dev.log('signIn OK uid=${u.uid} email=${u.email}', name: 'Auth');
      return AuthUser(
        uid: u.uid,
        email: u.email,
        name: u.displayName,
        birthday: u.metadata.creationTime ?? DateTime.now(),
      );
    } catch (e, st) {
      AuthDebugLog.authFailed(
        flow: 'signIn',
        error: e,
        stackTrace: st,
        identifier: identifier,
        resolvedEmail: email,
        step: 'firebase_sign_in',
      );
      rethrow;
    }
  }

  @override
  Future<AuthUser> signUp(String email, String password, String name) async {
    AuthDebugLog.logFirebaseContext();
    dev.log(
      'signUp START email=$email passwordLen=${password.length}',
      name: 'Auth',
    );

    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final u = cred.user!;
      dev.log('signUp OK uid=${u.uid}', name: 'Auth');
      return AuthUser(
        uid: u.uid,
        email: u.email,
        name: name,
        birthday: DateTime.now(),
      );
    } catch (e, st) {
      AuthDebugLog.authFailed(
        flow: 'signUp',
        error: e,
        stackTrace: st,
        identifier: email,
        step: 'firebase_create_user',
      );
      rethrow;
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }
}
