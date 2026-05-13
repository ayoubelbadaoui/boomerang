import 'package:boomerang/core/auth/user_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('user sessions roundtrip through storage encoding', () {
    final sessions = [
      UserSession(
        uid: 'uid_1',
        email: 'one@example.com',
        displayName: 'One',
        photoUrl: 'https://example.com/one.jpg',
        lastLogin: DateTime(2026, 5, 13, 20, 0),
      ),
      UserSession(
        uid: 'uid_2',
        email: 'two@example.com',
        displayName: 'Two',
        lastLogin: DateTime(2026, 5, 13, 20, 5),
      ),
    ];

    final encoded = UserSession.encodeList(sessions);
    final decoded = UserSession.decodeList(encoded);

    expect(decoded.length, sessions.length);
    expect(decoded[0].uid, 'uid_1');
    expect(decoded[0].email, 'one@example.com');
    expect(decoded[0].photoUrl, 'https://example.com/one.jpg');
    expect(decoded[1].uid, 'uid_2');
    expect(decoded[1].photoUrl, isNull);
  });
}
