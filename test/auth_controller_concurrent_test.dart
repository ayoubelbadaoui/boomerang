import 'dart:async';

import 'package:boomerang/core/auth/multi_account_manager.dart';
import 'package:boomerang/core/auth/session_storage.dart';
import 'package:boomerang/core/auth/user_session.dart';
import 'package:boomerang/features/auth/application/auth_controller.dart';
import 'package:boomerang/features/auth/domain/auth_user.dart';
import 'package:boomerang/features/auth/infrastructure/auth_repo.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthRepo implements AuthRepo {
  int signUpCalls = 0;
  int signInCalls = 0;
  Completer<AuthUser>? pendingSignUp;
  Completer<AuthUser>? pendingSignIn;
  Object? signUpError;

  @override
  AuthUser? get currentUser => null;

  @override
  Stream<AuthUser?> watch() => const Stream.empty();

  @override
  Future<AuthUser> signUp(String email, String password, String name) async {
    signUpCalls++;
    final pending = pendingSignUp;
    if (pending != null) {
      return pending.future;
    }
    if (signUpError != null) {
      throw signUpError!;
    }
    return AuthUser(
      uid: 'uid_$signUpCalls',
      email: email,
      name: name,
      birthday: DateTime(2000),
    );
  }

  @override
  Future<AuthUser> signIn(String emailOrUsername, String password) async {
    signInCalls++;
    final pending = pendingSignIn;
    if (pending != null) {
      return pending.future;
    }
    return AuthUser(
      uid: 'uid_$signInCalls',
      email: emailOrUsername,
      name: 'User',
      birthday: DateTime(2000),
    );
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<void> resetPassword(String email) async {}
}

class _NoopAccountManager extends MultiAccountManager {
  _NoopAccountManager()
    : super(storage: SessionStorage(), firebaseAuth: MockFirebaseAuth());

  @override
  Future<void> addAccount(UserSession session, {String? password}) async {}
}

void main() {
  group('AuthController concurrent auth', () {
    test('signup ignores concurrent calls while loading', () async {
      final repo = _FakeAuthRepo()..pendingSignUp = Completer<AuthUser>();
      final controller = AuthController(repo, _NoopAccountManager());

      final first = controller.signup('a@b.com', 'password123', 'Ayoub');
      expect(controller.state.loading, isTrue);
      expect(repo.signUpCalls, 1);

      final second = controller.signup('a@b.com', 'password123', 'Ayoub');
      await second;
      expect(repo.signUpCalls, 1);

      repo.pendingSignUp!.complete(
        AuthUser(
          uid: 'uid_1',
          email: 'a@b.com',
          name: 'Ayoub',
          birthday: DateTime(2000),
        ),
      );
      await first;

      expect(controller.state.loading, isFalse);
      expect(controller.state.success, 'Account created successfully');
      expect(controller.state.error, isNull);
      expect(repo.signUpCalls, 1);
    });

    test('login ignores concurrent calls while loading', () async {
      final repo = _FakeAuthRepo()..pendingSignIn = Completer<AuthUser>();
      final controller = AuthController(repo, _NoopAccountManager());

      final first = controller.login('a@b.com', 'password123');
      expect(controller.state.loading, isTrue);
      expect(repo.signInCalls, 1);

      final second = controller.login('a@b.com', 'password123');
      await second;
      expect(repo.signInCalls, 1);

      repo.pendingSignIn!.complete(
        AuthUser(
          uid: 'uid_1',
          email: 'a@b.com',
          name: 'User',
          birthday: DateTime(2000),
        ),
      );
      await first;

      expect(controller.state.loading, isFalse);
      expect(controller.state.success, 'Logged in successfully');
      expect(controller.state.error, isNull);
      expect(repo.signInCalls, 1);
    });
  });
}
