// 应用自己的鸿蒙桥接通道，Dart 端是 lib/utils/ohos/ohos_bridge.dart。
import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import { MovingPhotoSave } from './MovingPhotoSave';

export default class OhosBridgePlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;

  getUniqueClassName(): string {
    return 'OhosBridgePlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'piliplus/ohos');
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    MovingPhotoSave.cancel();
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'saveMovingPhoto':
        MovingPhotoSave.request(
          call.argument('imagePath') as string, call.argument('videoPath') as string, result);
        break;
      default:
        result.notImplemented();
    }
  }
}
