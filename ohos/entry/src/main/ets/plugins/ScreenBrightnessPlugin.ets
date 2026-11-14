// 屏幕亮度：实现 screen_brightness_platform_interface 默认的通道协议。
// 鸿蒙不允许普通应用修改系统亮度，「系统亮度」的读写都落在本窗口的亮度上。
import {
  AbilityAware,
  AbilityPluginBinding,
  EventChannel,
  FlutterPlugin,
  FlutterPluginBinding,
  Log,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import { EventSink, StreamHandler } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { settings } from '@kit.BasicServicesKit';

const TAG = 'ScreenBrightnessPlugin';
const CHANNEL = 'github.com/aaassseee/screen_brightness';

class SinkHolder implements StreamHandler {
  sink: EventSink | null = null;

  onListen(args: Object, events: EventSink): void {
    this.sink = events;
  }

  onCancel(args: Object): void {
    this.sink = null;
  }
}

export default class ScreenBrightnessPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  private applicationEvents: EventChannel | null = null;
  private systemEvents: EventChannel | null = null;
  private applicationSink = new SinkHolder();
  private systemSink = new SinkHolder();
  private context: common.UIAbilityContext | null = null;
  // 应用设置过的窗口亮度；null 表示跟随系统。
  private applied: number | null = null;
  private autoReset = true;
  private animate = true;

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    const messenger = binding.getBinaryMessenger();
    this.channel = new MethodChannel(messenger, CHANNEL);
    this.channel.setMethodCallHandler(this);
    this.applicationEvents = new EventChannel(messenger, `${CHANNEL}/application_brightness_changed`);
    this.applicationEvents.setStreamHandler(this.applicationSink);
    this.systemEvents = new EventChannel(messenger, `${CHANNEL}/system_brightness_changed`);
    this.systemEvents.setStreamHandler(this.systemSink);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.applicationEvents?.setStreamHandler(null);
    this.systemEvents?.setStreamHandler(null);
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context;
  }

  onDetachedFromAbility(): void {
    this.context = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'getSystemScreenBrightness':
        result.success(this.applied ?? this.systemBrightness());
        break;
      case 'getApplicationScreenBrightness':
        result.success(this.applied ?? this.systemBrightness());
        break;
      case 'setSystemScreenBrightness':
      case 'setApplicationScreenBrightness': {
        const value = call.argument('brightness') as number;
        this.apply(value, result, call.method === 'setSystemScreenBrightness');
        break;
      }
      case 'resetApplicationScreenBrightness':
        this.apply(null, result, false);
        break;
      case 'hasApplicationScreenBrightnessChanged':
        result.success(this.applied != null);
        break;
      case 'isAutoReset':
        result.success(this.autoReset);
        break;
      case 'setAutoReset':
        this.autoReset = call.argument('isAutoReset') as boolean;
        result.success(null);
        break;
      case 'isAnimate':
        result.success(this.animate);
        break;
      case 'setAnimate':
        this.animate = call.argument('isAnimate') as boolean;
        result.success(null);
        break;
      case 'canChangeSystemBrightness':
        result.success(false);
        break;
      default:
        result.notImplemented();
    }
  }

  private apply(value: number | null, result: MethodResult, asSystem: boolean): void {
    const context = this.context;
    if (context == null) {
      result.error('-10', 'Unexpected error on activity binding', null);
      return;
    }
    window.getLastWindow(context).then((win: window.Window) => {
      return win.setWindowBrightness(value == null ? -1 : Math.min(1, Math.max(0, value)));
    }).then(() => {
      this.applied = value;
      const current = value ?? this.systemBrightness();
      (asSystem ? this.systemSink : this.applicationSink).sink?.success(current);
      result.success(null);
    }).catch((e: Error) => {
      Log.e(TAG, `setWindowBrightness failed: ${JSON.stringify(e)}`);
      result.error('-1', 'Unable to change screen brightness', null);
    });
  }

  // 系统亮度设置项的取值范围是 0~255。读不到时返回 0.5。
  private systemBrightness(): number {
    const context = this.context;
    if (context == null) {
      return 0.5;
    }
    try {
      const raw = settings.getValueSync(context, settings.display.SCREEN_BRIGHTNESS_STATUS, '',
        settings.domainName.DEVICE_SHARED);
      const value = Number.parseFloat(raw);
      if (Number.isFinite(value)) {
        return Math.min(1, Math.max(0, value / 255));
      }
    } catch (e) {
      Log.e(TAG, `read system brightness failed: ${JSON.stringify(e)}`);
    }
    return 0.5;
  }
}
