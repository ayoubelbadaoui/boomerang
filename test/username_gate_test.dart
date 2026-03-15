import 'package:boomerang/features/auth/domain/username_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('username validation (nickname rules)', () {
    test('rejects empty', () {
      final res = validateUsername('');
      expect(res.isValid, false);
    });
    test('rejects invalid characters', () {
      final res = validateUsername('Bad*Name');
      expect(res.isValid, false);
    });
    test('accepts valid lowercase', () {
      final res = validateUsername('user.name_1');
      expect(res.isValid, true);
    });
  });
}
