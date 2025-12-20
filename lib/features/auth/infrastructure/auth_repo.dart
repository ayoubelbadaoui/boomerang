import 'package:boomerang/features/auth/domain/auth_user.dart';

abstract class AuthRepo {
  Stream<AuthUser?> watch();
  Future<AuthUser> signIn(String email, String password);
  Future<AuthUser> signUp(String email, String password, String name);
  Future<void> signOut();
  Future<void> resetPassword(String email);
}
