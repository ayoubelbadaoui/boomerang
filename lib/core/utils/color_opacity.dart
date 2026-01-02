// lets create an extension for color to add a withOpacity method
import 'dart:ui';

extension ColorExtension on Color {
  Color fade(double opacity) {
    return withValues(alpha: opacity * 255);
  }
}
