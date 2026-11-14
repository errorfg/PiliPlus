import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

/// Shows PQ/HLG video as HDR on iOS.
///
/// The player normally renders into a Flutter texture, which Flutter
/// composites as SDR. While [active] is set, the video is instead shown by
/// libmpv's `avfoundation` video output on the layer of a platform view
/// (`ios/Runner/HdrVideoView.swift`), which the system composites as HDR.
/// libmpv does no rendering of its own there, so its shaders and tone mapping
/// do not apply.
class IosHdrOutput {
  IosHdrOutput(this.player) {
    _subscription = player.stream.videoParams.listen((_) => _update());
    player.release.add(_dispose);
  }

  final Player player;

  /// Whether the video widget must show the HDR view above the texture.
  final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  StreamSubscription<VideoParams>? _subscription;
  bool _attached = false;
  bool _suspended = false;
  bool _disposed = false;

  /// Whether the video is currently shown on the HDR layer.
  bool get attached => _attached;

  /// Shows HDR video through the texture (tone mapped) while set. Used while
  /// the picture is taken from the texture, as in picture-in-picture.
  set suspended(bool value) {
    if (_suspended == value) return;
    _suspended = value;
    _update();
  }

  String _property(String name) {
    try {
      return player.getProperty(name);
    } catch (_) {
      return '';
    }
  }

  /// Decides from the decoder's parameters. They are empty while the video
  /// output is being recreated; nothing is decided then.
  void _update() {
    if (_disposed) return;
    final gamma = _property('video-params/gamma');
    if (gamma.isEmpty) return;
    final useHdr =
        !_suspended &&
        (gamma == 'pq' || gamma == 'hlg') &&
        _property('hwdec-current').contains('videotoolbox');
    if (!useHdr && active.value) detach();
    active.value = useHdr;
  }

  /// Changes the video output with the video track switched off, so that the
  /// decoder is created for the new output. A decoder that already exists is
  /// kept across an output change, and the two outputs need different ones:
  /// the texture takes 8 bit frames, the layer takes the 10 bit ones.
  void _switchOutput(Map<String, String> options) {
    final vid = _property('vid');
    final hasVideo = vid.isNotEmpty && vid != 'no';
    if (hasVideo) player.setProperty('vid', 'no');
    options.forEach(player.setProperty);
    if (hasVideo) player.setProperty('vid', vid);
  }

  /// Lets the decoder's frames go to the layer at address [layer].
  void attach(int layer) {
    if (_disposed || !active.value || _attached) return;
    _attached = true;
    _switchOutput({
      'wid': layer.toString(),
      // the OpenGL ES path makes the decoder convert 10 bit video to 8 bit
      'hwdec-image-format': 'p010',
      'vo': 'avfoundation',
    });
  }

  /// Goes back to rendering into the Flutter texture.
  void detach() {
    if (!_attached) return;
    _attached = false;
    if (_disposed) return;
    _switchOutput({
      'hwdec-image-format': 'no',
      'vo': 'libmpv',
      'wid': '-1',
    });
  }

  Future<void> _dispose() async {
    _disposed = true;
    await _subscription?.cancel();
  }
}

/// [child] (the video texture), covered by the HDR view while
/// [IosHdrOutput.active] is set.
class IosHdrVideo extends StatelessWidget {
  const IosHdrVideo({super.key, required this.output, required this.child});

  final IosHdrOutput output;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: output.active,
      child: child,
      builder: (context, active, child) => Stack(
        children: [
          child!,
          if (active) Positioned.fill(child: _HdrView(output: output)),
        ],
      ),
    );
  }
}

class _HdrView extends StatefulWidget {
  const _HdrView({required this.output});

  final IosHdrOutput output;

  @override
  State<_HdrView> createState() => _HdrViewState();
}

class _HdrViewState extends State<_HdrView> {
  static const _viewType = 'piliplus/hdr_video';

  Future<void> _onCreated(int id) async {
    final layer = await MethodChannel(
      '${_viewType}_$id',
    ).invokeMethod<int>('layer');
    if (mounted && layer != null) widget.output.attach(layer);
  }

  @override
  void dispose() {
    widget.output.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UiKitView(
      viewType: _viewType,
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      onPlatformViewCreated: _onCreated,
    );
  }
}
