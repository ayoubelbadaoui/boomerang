import 'dart:developer' as dev;

import 'package:boomerang/core/auth/multi_account_manager.dart';
import 'package:boomerang/core/auth/user_session.dart';
import 'package:boomerang/features/auth/domain/auth_state.dart';
import 'package:boomerang/features/auth/domain/auth_user.dart';
import 'package:boomerang/features/auth/infrastructure/auth_repo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boomerang/core/utils/auth_debug_log.dart';
import 'package:boomerang/core/utils/auth_error_mapper.dart';
import 'package:boomerang/core/utils/perf_log.dart';

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
    if (state.loading) return;
    final loginClock = Stopwatch()..start();
    try {
      state = const AuthState(loading: true);

      PerfLog.event('login START');
      dev.log('[multi-account] login START for $emailOrUsername');

      if (previousAccount != null) {
        dev.log(
          '[multi-account] login: storing previous account '
          '${previousAccount.uid} (${previousAccount.displayName})',
        );
        await PerfLog.track(
          'login.storePreviousAccount',
          () => _accountManager.addAccount(previousAccount),
        );
      }

      final user = await PerfLog.track(
        'login.signIn',
        () => _repo.signIn(emailOrUsername, password),
      );
      dev.log('[multi-account] login: signIn OK uid=${user.uid}');

      final resolvedEmail = user.email?.trim() ?? '';
      if (resolvedEmail.isEmpty) {
        throw StateError('Authenticated account is missing an email.');
      }

      await PerfLog.track(
        'login.persistSession',
        () => _accountManager.addAccount(
          UserSession(
            uid: user.uid,
            email: resolvedEmail,
            displayName: user.name ?? '',
            lastLogin: DateTime.now(),
          ),
          password: password,
        ),
      );
      dev.log('[multi-account] login: addAccount DONE');

      PerfLog.event(
        'login DONE',
        'totalMs=${loginClock.elapsedMilliseconds}',
      );
      state = const AuthState(success: 'Logged in successfully');
    } catch (e, st) {
      AuthDebugLog.authFailed(
        flow: 'login',
        error: e,
        stackTrace: st,
        identifier: emailOrUsername,
        step: 'auth_controller',
      );
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
    if (state.loading) return;
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
    } catch (e, st) {
      AuthDebugLog.authFailed(
        flow: 'signup',
        error: e,
        stackTrace: st,
        identifier: email,
        step: 'auth_controller',
      );
      state = AuthState(error: AuthErrorMapper.map(e));
    }
  }

  Future<void> logout() async {
    state = const AuthState(loading: true);
    Object? signOutError;
    try {
      await _repo.signOut();
    } catch (e) {
      signOutError = e;
      dev.log('[multi-account] logout signOut FAILED: $e');
    }

    try {
      await _accountManager.clearLocalAuthArtifacts();
    } catch (e) {
      dev.log('[multi-account] logout local clear FAILED: $e');
      signOutError ??= e;
    }

    if (signOutError != null) {
      state = AuthState(error: AuthErrorMapper.map(signOutError));
    } else {
      state = const AuthState(success: 'Logged out');
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
