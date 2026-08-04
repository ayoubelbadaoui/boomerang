import 'dart:io';

import 'package:flutter/services.dart';

/// Ref-counted immersive SystemChrome helper for fullscreen routes.
///
/// Nested fullscreen pages (viewer → pager, camera → editor, etc.) must not
/// restore system overlays when an inner route disposes while an outer one is
/// still immersive.
class ImmersiveSystemUi {
  ImmersiveSystemUi._();

  static int _depth = 0;

  /// Hide status/navigation overlays. Safe to call from nested routes.
  static void enter() {
    _depth++;
    if (_depth == 1) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
    }
  }

  /// Restore overlays only when the last immersive route leaves.
  ///
  /// On Android this returns to [SystemUiMode.edgeToEdge] (set in `main.dart`)
  /// instead of `manual`+all overlays, which would exit edge-to-edge and cause
  /// status/nav bar flicker and layout jumps after leaving fullscreen video.
  static void leave() {
    if (_depth <= 0) return;
    _depth--;
    if (_depth == 0) {
      if (Platform.isAndroid) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      } else {
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        );
      }
    }
  }
}
