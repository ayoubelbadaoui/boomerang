import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';

/// Wall-clock diagnostics for the app-start → sign-in → first-feed path.
///
/// Every line is prefixed with `[PERFLOG]` so a whole session can be pulled
/// with a single grep from `flutter logs`, `adb logcat`, or the Xcode
/// console. `t+<ms>` is time since process start, `took=<ms>` is the duration
/// of the step itself.
class PerfLog {
  PerfLog._();

  static final Stopwatch _appClock = Stopwatch()..start();

  static int get appMs => _appClock.elapsedMilliseconds;

  /// Point-in-time marker.
  static void event(String name, [String detail = '']) {
    _emit('$name${detail.isEmpty ? '' : ' $detail'} t+${appMs}ms');
  }

  /// Times an async step and logs success/failure with duration.
  static Future<T> track<T>(
    String name,
    Future<T> Function() run, {
    String detail = '',
  }) async {
    final sw = Stopwatch()..start();
    try {
      final result = await run();
      _emit(
        '$name OK${detail.isEmpty ? '' : ' $detail'} '
        'took=${sw.elapsedMilliseconds}ms t+${appMs}ms',
      );
      return result;
    } catch (e) {
      _emit(
        '$name FAILED${detail.isEmpty ? '' : ' $detail'} '
        'took=${sw.elapsedMilliseconds}ms t+${appMs}ms err=$e',
      );
      rethrow;
    }
  }

  static void _emit(String message) {
    // debugPrint reaches `flutter logs` / logcat / Xcode console;
    // dev.log reaches DevTools. Both so no collection method misses lines.
    debugPrint('[PERFLOG] $message');
    dev.log(message, name: 'PERFLOG');
  }
}
