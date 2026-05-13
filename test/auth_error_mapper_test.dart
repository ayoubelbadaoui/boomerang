import 'package:boomerang/core/utils/auth_error_mapper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthErrorMapper', () {
    test('maps invalid-email', () {
      final error = FirebaseAuthException(code: 'invalid-email');
      expect(
        AuthErrorMapper.map(error),
        'The email address is badly formatted.',
      );
    });

    test('maps login credential failures to generic login error', () {
      final wrongPassword = FirebaseAuthException(code: 'wrong-password');
      final userNotFound = FirebaseAuthException(code: 'user-not-found');
      expect(AuthErrorMapper.map(wrongPassword), 'Incorrect email or password.');
      expect(AuthErrorMapper.map(userNotFound), 'Incorrect email or password.');
    });

    test('maps requires-recent-login', () {
      final error = FirebaseAuthException(code: 'requires-recent-login');
      expect(
        AuthErrorMapper.map(error),
        'For security, sign in again with your password, then retry.',
      );
    });

    test('maps unknown errors to fallback message', () {
      expect(AuthErrorMapper.map(StateError('boom')), 'Something went wrong. Please try again.');
    });
  });
}
