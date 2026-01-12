import 'package:boomerang/features/auth/domain/username_gate.dart';
import 'package:boomerang/features/auth/domain/username_validation.dart';
import 'package:boomerang/features/auth/presentation/choose_username_page.dart';
import 'package:boomerang/features/feed/presentation/home_shell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('username validation', () {
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

  group('username gate redirect', () {
    test('missing username redirects to choose page', () {
      final r = usernameGateRedirect(
        signedIn: true,
        hasUsername: false,
        currentPath: '/home',
      );
      expect(r, ChooseUsernamePage.routeName);
    });
    test('existing username stays on home', () {
      final r = usernameGateRedirect(
        signedIn: true,
        hasUsername: true,
        currentPath: '/home',
      );
      expect(r, null);
    });
    test('existing username on choose page redirects home', () {
      final r = usernameGateRedirect(
        signedIn: true,
        hasUsername: true,
        currentPath: ChooseUsernamePage.routeName,
      );
      expect(r, HomeShell.routeName);
    });
  });
}
