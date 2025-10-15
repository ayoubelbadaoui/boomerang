import 'package:boomerang/features/auth/domain/auth_user.dart';

abstract class AuthRepo {
  Stream<AuthUser?> watch();
  Future<AuthUser> signIn(String email, String password);
  Future<AuthUser> signUp(
    String email,
    String password,
    String name,
    String birthday,
  );
  Future<void> signOut();
}
