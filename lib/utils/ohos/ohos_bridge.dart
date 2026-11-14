import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 应用自己的鸿蒙桥接通道，原生端是 `ohos/entry` 里的 `OhosBridgePlugin`。
abstract final class OhosBridge {
  static const _channel = MethodChannel('piliplus/ohos');

  static void init() {
    if (!PlatformUtils.isOhos) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onHdrPipState':
          hdrPipActive.value = call.arguments == true;
        case 'onHdrPipAction':
          if (call.arguments case final Map args) {
            if (args['event'] case final String event) {
              onHdrPipAction?.call(event, args['status'] as int?);
            }
          }
      }
    });
  }

  /// 把一张静态图和一段视频保存为图库里的动态照片。系统会弹出确认层，
  /// 用户取消时返回 false；失败时抛出 [PlatformException]。
  static Future<bool> saveMovingPhoto({
    required String imagePath,
    required String videoPath,
  }) async {
    return await _channel.invokeMethod<bool>('saveMovingPhoto', {
          'imagePath': imagePath,
          'videoPath': videoPath,
        }) ??
        false;
  }

  // HDR 视频的画中画：HDR 画面是一个由系统合成的独立图层，直接把这一层交给
  // 系统放进小窗，HDR 保持点亮。小窗里只有视频，没有 Flutter 画的弹幕和字幕。
  // 普通视频的画中画见 ohos_pip.dart。

  /// HDR 视频是否正显示在画中画小窗里。
  static final hdrPipActive = ValueNotifier<bool>(false);

  /// 已让系统在应用退到后台时自动进入 HDR 画中画。
  static bool hdrPipAutoArmed = false;

  /// 小窗上的按钮，事件与 [OhosPip.onAction] 相同。
  static void Function(String event, int? status)? onHdrPipAction;

  static Future<bool> startHdrPip({required int width, required int height}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('hdrPipStart', {
            'width': width,
            'height': height,
          }) ??
          false;
      if (ok) hdrPipActive.value = true;
      return ok;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setHdrPipAuto(
    bool enable, {
    int width = 16,
    int height = 9,
  }) async {
    if (!enable && !hdrPipAutoArmed) return;
    try {
      final ok = await _channel.invokeMethod<bool>('hdrPipSetAuto', {
            'enable': enable,
            'width': width,
            'height': height,
          }) ??
          false;
      hdrPipAutoArmed = enable && ok;
    } catch (_) {
      hdrPipAutoArmed = false;
    }
  }

  static Future<void> updateHdrPipPlaying(bool playing) async {
    if (!hdrPipActive.value && !hdrPipAutoArmed) return;
    try {
      await _channel.invokeMethod('hdrPipUpdatePlaying', {'playing': playing});
    } catch (_) {}
  }
}
