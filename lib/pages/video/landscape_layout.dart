import 'dart:ui' show clampDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Width of the player in a landscape window, beside the column on its right.
/// [availableWidth] leaves out the system's insets at the sides.
double landscapeVideoWidth(double availableWidth, double height) {
  final width =
      clampDouble(height / availableWidth * 1.08, 0.5, 0.7) * availableWidth;
  return availableWidth >= 560
      ? availableWidth - clampDouble(availableWidth - width, 280, 425)
      : width;
}

/// Width of the strip iOS keeps along the right edge for its vertical bars,
/// which it reports as an inset on that side only (iPhone Duo). The video page
/// has no bars to put there and draws over it, under the status bar.
double verticalBarStripWidth(EdgeInsets viewPadding) =>
    defaultTargetPlatform == .iOS && viewPadding.left == 0
    ? viewPadding.right
    : 0;
