import 'package:boomerang/features/auth/domain/auth_state.dart';
import 'package:boomerang/features/auth/domain/auth_user.dart';
import 'package:boomerang/features/auth/infrastructure/auth_repo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:boomerang/core/utils/auth_error_mapper.dart';

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repo) : super(const AuthState());
  final AuthRepo _repo;

  Stream<AuthUser?> watch() => _repo.watch();

  Future<void> login(String email, String password) async {
    try {
      state = const AuthState(loading: true);
      await _repo.signIn(email, password);
      state = const AuthState(success: 'Logged in successfully');
    } catch (e) {
      state = AuthState(error: AuthErrorMapper.map(e));
    }
  }

  Future<void> signup(String email, String password, String name) async {
    try {
      state = const AuthState(loading: true);
      await _repo.signUp(email, password, name);
      state = const AuthState(success: 'Account created successfully');
    } catch (e) {
      state = AuthState(error: AuthErrorMapper.map(e));
    }
  }

  Future<void> logout() async => _repo.signOut();
}
