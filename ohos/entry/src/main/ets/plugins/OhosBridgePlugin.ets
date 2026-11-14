// 应用自己的鸿蒙桥接通道，Dart 端是 lib/utils/ohos/ohos_bridge.dart。
import {
  AbilityAware,
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import { MovingPhotoSave } from './MovingPhotoSave';
import { HdrVideoViewFactory } from './HdrVideoView';
import { HdrPip } from './HdrPip';

export default class OhosBridgePlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;

  getUniqueClassName(): string {
    return 'OhosBridgePlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'piliplus/ohos');
    this.channel.setMethodCallHandler(this);
    HdrPip.channel = this.channel;
    binding.getPlatformViewRegistry()?.registerViewFactory(
      'piliplus/hdr_video', new HdrVideoViewFactory(binding.getBinaryMessenger()));
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    HdrPip.channel = null;
    HdrPip.release();
    MovingPhotoSave.cancel();
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    HdrPip.context = binding.getAbility().context;
  }

  onDetachedFromAbility(): void {
    HdrPip.release();
    HdrPip.context = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'saveMovingPhoto':
        MovingPhotoSave.request(
          call.argument('imagePath') as string, call.argument('videoPath') as string, result);
        break;
      case 'hdrPipStart':
        HdrPip.start(call.argument('width') as number, call.argument('height') as number)
          .then((ok: boolean) => result.success(ok));
        break;
      case 'hdrPipSetAuto':
        HdrPip.setAutoStart(call.argument('enable') as boolean,
          call.argument('width') as number, call.argument('height') as number)
          .then((ok: boolean) => result.success(ok));
        break;
      case 'hdrPipUpdatePlaying':
        HdrPip.updatePlaying(call.argument('playing') as boolean);
        result.success(null);
        break;
      case 'hdrPipStop':
        HdrPip.stop().then(() => result.success(null));
        break;
      default:
        result.notImplemented();
    }
  }
}
