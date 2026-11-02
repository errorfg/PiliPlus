import 'package:flutter/services.dart' show StandardMessageCodec;
import 'package:material_ui/material_ui.dart';

/// iOS's own Liquid Glass (UIGlassEffect), for content laid over it: a capsule
/// unless [cornerRadius] is given. It takes no touches.
///
/// Keep clips out of its ancestors: Flutter masks a platform view under a
/// clip, and an effect view under a mask stops sampling what is behind it.
class NativeGlass extends StatelessWidget {
  const NativeGlass({super.key, this.cornerRadius});

  final double? cornerRadius;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return IgnorePointer(
      child: UiKitView(
        // The creation params are all the view is told.
        key: ValueKey(brightness),
        viewType: 'piliplus/native_glass',
        creationParams: <String, Object?>{
          'cornerRadius': cornerRadius,
          'dark': brightness == .dark,
        },
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}
