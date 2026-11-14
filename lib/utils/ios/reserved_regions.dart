import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The parts of the app's view that iOS reserves for system elements, in
/// logical pixels: on iPhone Duo, the status bar with the Dynamic Island at the
/// top of the strip along the right edge, which grows and shrinks with the
/// island. Read in `ios/Runner/ReservedRegionsPlugin.swift`.
///
/// Empty on other platforms and before iOS 27.1.
abstract final class ReservedRegions {
  static const _channel = MethodChannel(
    'com.example.piliplus/reserved_regions',
  );

  static final ValueNotifier<List<Rect>> regions = ValueNotifier(const []);

  static bool _observing = false;

  /// Starts following the regions, if it has not already.
  static void observe() {
    if (_observing || !Platform.isIOS) return;
    _observing = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'didChange') {
        regions.value = decode(call.arguments);
      }
    });
    unawaited(_observe());
  }

  static Future<void> _observe() async {
    try {
      regions.value = decode(await _channel.invokeMethod<Object?>('observe'));
    } catch (e) {
      if (kDebugMode) debugPrint('ReservedRegions observe: $e');
    }
  }

  @visibleForTesting
  static List<Rect> decode(Object? regions) => [
    for (final region in (regions as List<Object?>? ?? const []))
      if (region case [
        final num left,
        final num top,
        final num right,
        final num bottom,
        ...,
      ])
        Rect.fromLTRB(
          left.toDouble(),
          top.toDouble(),
          right.toDouble(),
          bottom.toDouble(),
        ),
  ];
}

/// The status bar at the top of the strip iOS keeps along the right edge, of
/// width [stripWidth], in a view of [size]; null where there is none.
///
/// The camera at the other end of the strip is left out: nothing is pinned
/// under it.
Rect? statusBarInStrip({
  required List<Rect> regions,
  required Size size,
  required double stripWidth,
}) {
  if (stripWidth <= 0) return null;
  Rect? result;
  for (final region in regions) {
    if (region.center.dx < size.width - stripWidth ||
        region.center.dy > size.height / 2) {
      continue;
    }
    result = result?.expandToInclude(region) ?? region;
  }
  return result;
}
