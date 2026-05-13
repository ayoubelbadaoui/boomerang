import 'package:boomerang/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validators.emailOrUsername', () {
    test('accepts valid email', () {
      expect(Validators.emailOrUsername('user@example.com'), isNull);
    });

    test('accepts valid username', () {
      expect(Validators.emailOrUsername('username_123'), isNull);
    });

    test('rejects short username', () {
      expect(
        Validators.emailOrUsername('ab'),
        'Enter a valid username',
      );
    });

    test('rejects invalid email format', () {
      expect(
        Validators.emailOrUsername('not-an-email@'),
        'Enter a valid email',
      );
    });
  });
}
