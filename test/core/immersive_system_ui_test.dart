import 'package:boomerang/core/utils/immersive_system_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Drain leftover depth between tests.
  tearDown(() {
    for (var i = 0; i < 8; i++) {
      ImmersiveSystemUi.leave();
    }
  });

  test('nested enter/leave only restores on last leave', () {
    ImmersiveSystemUi.enter();
    ImmersiveSystemUi.enter();
    ImmersiveSystemUi.leave(); // still immersive
    ImmersiveSystemUi.leave(); // restored
    ImmersiveSystemUi.leave(); // no-op when depth is 0
  });

  test('leave is a no-op at depth 0 without throwing', () {
    // Binding accepts SystemChrome calls in widget tests.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    ImmersiveSystemUi.leave();
    ImmersiveSystemUi.enter();
    ImmersiveSystemUi.leave();
  });
}
