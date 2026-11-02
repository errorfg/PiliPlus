import 'dart:ui' show clampDouble;

/// Width of the player in a landscape window, beside the column on its right.
/// [availableWidth] leaves out the system's insets at the sides.
double landscapeVideoWidth(double availableWidth, double height) {
  final width =
      clampDouble(height / availableWidth * 1.08, 0.5, 0.7) * availableWidth;
  return availableWidth >= 560
      ? availableWidth - clampDouble(availableWidth - width, 280, 425)
      : width;
}
