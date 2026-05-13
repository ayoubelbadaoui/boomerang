import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('router no longer contains phone verification route or redirect', () {
    final file = File('lib/router.dart');
    final source = file.readAsStringSync();

    expect(source.contains('/verify/phone'), isFalse);
    expect(source.contains('PhoneVerificationPage'), isFalse);
    expect(source.contains('userPhoneVerificationStatusProvider'), isFalse);
  });
}
