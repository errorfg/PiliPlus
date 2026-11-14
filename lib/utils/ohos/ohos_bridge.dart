import 'package:flutter/services.dart';

/// 应用自己的鸿蒙桥接通道，原生端是 `ohos/entry` 里的 `OhosBridgePlugin`。
abstract final class OhosBridge {
  static const _channel = MethodChannel('piliplus/ohos');

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
}
