import 'package:boomerang/features/auth/domain/auth_state.dart';
import 'package:boomerang/features/auth/domain/auth_user.dart';
import 'package:boomerang/features/auth/infrastructure/auth_repo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repo) : super(const AuthState());
  final AuthRepo _repo;

  Stream<AuthUser?> watch() => _repo.watch();

  Future<void> login(String email, String password) async {
    try {
      state = const AuthState(loading: true);
      await _repo.signIn(email, password);
      state = const AuthState();
    } catch (e) {
      state = AuthState(error: e.toString());
    }
  }

  Future<void> signup(
    String email,
    String password,
    String name,
    String birthday,
  ) async {
    try {
      state = const AuthState(loading: true);
      await _repo.signUp(email, password, name, birthday);
      state = const AuthState();
    } catch (e) {
      state = AuthState(error: e.toString());
    }
  }

  Future<void> logout() async => _repo.signOut();
}
