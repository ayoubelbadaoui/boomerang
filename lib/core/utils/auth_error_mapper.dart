import 'package:firebase_auth/firebase_auth.dart';

class AuthErrorMapper {
  AuthErrorMapper._();

  static String map(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'The email address is badly formatted.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'user-not-found':
        case 'wrong-password':
          return 'Incorrect email or password.';
        case 'email-already-in-use':
          return 'An account already exists for that email.';
        case 'weak-password':
          return 'Password is too weak. Try a stronger one.';
        case 'too-many-requests':
          return 'Too many attempts. Please try again later.';
        case 'operation-not-allowed':
          return 'This sign-in method is not enabled.';
        default:
          return 'Authentication failed. Please try again.';
      }
    }
    return 'Something went wrong. Please try again.';
  }
}

