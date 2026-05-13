import 'dart:developer' as dev;

import 'package:boomerang/core/auth/multi_account_manager.dart';
import 'package:boomerang/core/auth/user_session.dart';
import 'package:boomerang/features/auth/domain/auth_state.dart';
import 'package:boomerang/features/auth/domain/auth_user.dart';
import 'package:boomerang/features/auth/infrastructure/auth_repo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boomerang/core/utils/auth_error_mapper.dart';

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repo, this._accountManager) : super(const AuthState());
  final AuthRepo _repo;
  final MultiAccountManager _accountManager;

  Stream<AuthUser?> watch() => _repo.watch();

  /// Log in a new user. If [previousAccount] is provided, it will be
  /// persisted to storage first so it isn't lost when signIn replaces
  /// the Firebase session.
  Future<void> login(
    String emailOrUsername,
    String password, {
    UserSession? previousAccount,
  }) async {
    try {
      state = const AuthState(loading: true);

      dev.log('[multi-account] login START for $emailOrUsername');

      if (previousAccount != null) {
        dev.log(
          '[multi-account] login: storing previous account '
          '${previousAccount.uid} (${previousAccount.displayName})',
        );
        await _accountManager.addAccount(previousAccount);
      }

      final user = await _repo.signIn(emailOrUsername, password);
      dev.log('[multi-account] login: signIn OK uid=${user.uid}');

      final resolvedEmail = user.email?.trim() ?? '';
      if (resolvedEmail.isEmpty) {
        throw StateError('Authenticated account is missing an email.');
      }

      await _accountManager.addAccount(
        UserSession(
          uid: user.uid,
          email: resolvedEmail,
          displayName: user.name ?? '',
          lastLogin: DateTime.now(),
        ),
        password: password,
      );
      dev.log('[multi-account] login: addAccount DONE');

      state = const AuthState(success: 'Logged in successfully');
    } catch (e) {
      dev.log('[multi-account] login FAILED: $e');
      state = AuthState(error: AuthErrorMapper.map(e));
    }
  }

  Future<void> signup(
    String email,
    String password,
    String name, {
    UserSession? previousAccount,
  }) async {
    try {
      state = const AuthState(loading: true);

      if (previousAccount != null) {
        await _accountManager.addAccount(previousAccount);
      }

      final user = await _repo.signUp(email, password, name);

      await _accountManager.addAccount(
        UserSession(
          uid: user.uid,
          email: user.email ?? email,
          displayName: user.name ?? name,
          lastLogin: DateTime.now(),
        ),
        password: password,
      );

      state = const AuthState(success: 'Account created successfully');
    } catch (e) {
      state = AuthState(error: AuthErrorMapper.map(e));
    }
  }

  Future<void> logout() async {
    try {
      state = const AuthState(loading: true);
      await _repo.signOut();
      state = const AuthState(success: 'Logged out');
    } catch (e) {
      state = AuthState(error: AuthErrorMapper.map(e));
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      state = const AuthState(loading: true);
      await _repo.resetPassword(email);
      state = const AuthState(
        success: 'Password reset email sent. Check your inbox.',
      );
    } catch (e) {
      state = AuthState(error: AuthErrorMapper.map(e));
    }
  }
}
