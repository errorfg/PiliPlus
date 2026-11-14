import 'dart:async';

import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 鸿蒙的画中画。原生部分是 floating 插件的鸿蒙实现：进入画中画时把 Flutter
/// 的画面切到画中画窗口里，页面此时只显示播放器，与安卓的做法相同。
abstract final class OhosPip {
  static const _channel = MethodChannel('floating');

  static bool _isAvailable = false;
  static bool get isAvailable => _isAvailable;

  /// 当前是否显示在画中画窗口里。页面要随它重建。
  static final mode = ValueNotifier<bool>(false);
  static bool get isPipMode => mode.value;

  /// 画中画窗口上的按钮：`playbackStateChanged`（status 1 播放、0 暂停）、
  /// `fastForward`、`fastBackward`。
  static void Function(String event, int? status)? onAction;

  static Future<void> init() async {
    if (!PlatformUtils.isOhos) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPipChanged':
          mode.value = call.arguments == true;
        case 'onPipAction':
          if (call.arguments case final Map args) {
            if (args['event'] case final String event) {
              onAction?.call(event, args['status'] as int?);
            }
          }
      }
    });
    try {
      _isAvailable = await _channel.invokeMethod<bool>('pipAvailable') ?? false;
    } catch (_) {
      _isAvailable = false;
    }
  }

  /// [autoEnter] 为 true 时不立即进入，而是让系统在应用退到后台时进入。
  static Future<void> enter({
    required int? width,
    required int? height,
    bool autoEnter = false,
  }) async {
    if (!_isAvailable) return;
    // 系统接受的宽高比范围是 1:2.39 到 2.39:1
    var numerator = 16;
    var denominator = 9;
    if (width != null && height != null && width > 0 && height > 0) {
      final ratio = width / height;
      if (ratio >= 1 / 2.39 && ratio <= 2.39) {
        numerator = width;
        denominator = height;
      } else if (height > width) {
        numerator = 9;
        denominator = 16;
      }
    }
    try {
      await _channel.invokeMethod('enablePip', {
        'numerator': numerator,
        'denominator': denominator,
        'autoEnable': autoEnter,
      });
    } catch (_) {}
  }

  static Future<void> disableAutoEnter() async {
    if (!_isAvailable) return;
    try {
      await _channel.invokeMethod('setAutoPip', {'auto': false});
    } catch (_) {}
  }

  static Future<void> updatePlaying(bool playing) async {
    if (!_isAvailable || !isPipMode) return;
    try {
      await _channel.invokeMethod('updatePipControlStatus', {
        'playing': playing,
      });
    } catch (_) {}
  }
}
