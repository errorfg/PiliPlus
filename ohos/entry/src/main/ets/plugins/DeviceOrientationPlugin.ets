// 屏幕方向感应：实现上游 native_device_orientation 分叉的通道协议
// （方法通道 pause/resume，事件通道按重力方向上报 DeviceOrientation 的名称）。
import {
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
import { sensor } from '@kit.SensorServiceKit';
import { display } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { settings } from '@kit.BasicServicesKit';

const TAG = 'DeviceOrientationPlugin';
// 屏幕平面内的重力角偏离当前方向多少度才切换。竖横分界在 45°，两侧各留 20° 防抖。
const SWITCH_MARGIN = 20;
// 设备接近平放时重力在屏幕平面内的分量很小，方向不可靠，不上报。
const MIN_PLANAR_GRAVITY = 3.0;
// 三折叠全部展开时，传感器坐标轴上的方向对应的屏幕方向。
const EXPANDED_MAP: Record<string, string> = {
  'portraitUp': 'landscapeLeft',
  'portraitDown': 'landscapeRight',
  'landscapeLeft': 'portraitDown',
  'landscapeRight': 'portraitUp'
};

export default class DeviceOrientationPlugin implements FlutterPlugin, MethodCallHandler, StreamHandler {
  private channel: MethodChannel | null = null;
  private eventChannel: EventChannel | null = null;
  private sink: EventSink | null = null;
  private context: common.Context | null = null;
  private listening = false;
  private withAutoRotate = false;
  // 按传感器坐标轴判断出的方向（未做折叠态换算）。
  private current: string | null = null;
  // 最近一次上报给 Dart 的方向。
  private reported: string | null = null;
  // 三折叠全部展开时，屏幕的正方向相对传感器坐标轴转了 90°。
  private fullyExpanded = false;
  private foldListening = false;
  private onFoldStatus = (status: display.FoldStatus): void => {
    const expanded = status === display.FoldStatus.FOLD_STATUS_EXPANDED_WITH_SECOND_EXPANDED;
    if (expanded !== this.fullyExpanded) {
      this.fullyExpanded = expanded;
      this.report();
    }
  };
  private onGravity = (data: sensor.GravityResponse): void => this.handle(data.x, data.y);

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext();
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'native_device_orientation');
    this.channel.setMethodCallHandler(this);
    this.eventChannel = new EventChannel(binding.getBinaryMessenger(), 'native_device_orientation_events');
    this.eventChannel.setStreamHandler(this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.stop();
    this.channel?.setMethodCallHandler(null);
    this.eventChannel?.setStreamHandler(null);
    this.sink = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'pause':
        this.stop();
        result.success(null);
        break;
      case 'resume':
        if (this.sink != null) {
          this.start();
        }
        result.success(null);
        break;
      default:
        result.notImplemented();
    }
  }

  onListen(args: Object, events: EventSink): void {
    this.sink = events;
    this.withAutoRotate = (args as Map<string, Object>)?.get('checkIsAutoRotate') === true;
    this.current = null;
    this.reported = null;
    this.start();
  }

  onCancel(args: Object): void {
    this.stop();
    this.sink = null;
  }

  private start(): void {
    if (this.listening) {
      return;
    }
    try {
      this.fullyExpanded =
        display.getFoldStatus() === display.FoldStatus.FOLD_STATUS_EXPANDED_WITH_SECOND_EXPANDED;
      display.on('foldStatusChange', this.onFoldStatus);
      this.foldListening = true;
    } catch (e) {
      Log.e(TAG, `fold status unavailable: ${JSON.stringify(e)}`);
    }
    try {
      sensor.on(sensor.SensorId.GRAVITY, this.onGravity, { interval: 'normal' });
      this.listening = true;
    } catch (e) {
      Log.e(TAG, `sensor.on failed: ${JSON.stringify(e)}`);
    }
  }

  private stop(): void {
    if (!this.listening) {
      return;
    }
    try {
      sensor.off(sensor.SensorId.GRAVITY, this.onGravity);
    } catch (e) {
      Log.e(TAG, `sensor.off failed: ${JSON.stringify(e)}`);
    }
    this.listening = false;
    if (this.foldListening) {
      try {
        display.off('foldStatusChange', this.onFoldStatus);
      } catch (e) {
        Log.e(TAG, `display.off failed: ${JSON.stringify(e)}`);
      }
      this.foldListening = false;
    }
  }

  // 系统的「自动旋转」开关。读不到时按开启处理。
  private autoRotateEnabled(): boolean {
    if (this.context == null) {
      return true;
    }
    try {
      return settings.getValueSync(this.context, settings.general.ACCELEROMETER_ROTATION_STATUS, '1') === '1';
    } catch (e) {
      Log.e(TAG, `read auto-rotate setting failed: ${JSON.stringify(e)}`);
      return true;
    }
  }

  // x、y 是重力在设备坐标轴上的分量：竖直正立时 y≈+9.8，逆时针转 90° 后 x≈+9.8。
  private handle(x: number, y: number): void {
    if (Math.hypot(x, y) < MIN_PLANAR_GRAVITY) {
      return;
    }
    const theta = Math.atan2(x, y) * 180 / Math.PI;
    const next = this.classify(theta);
    if (next === this.current) {
      return;
    }
    this.current = next;
    this.report();
  }

  private report(): void {
    if (this.current == null) {
      return;
    }
    const next = this.fullyExpanded ? EXPANDED_MAP[this.current] : this.current;
    if (next === this.reported) {
      return;
    }
    this.reported = next;
    if (this.withAutoRotate) {
      const payload = new Map<string, Object>();
      payload.set('orientation', next);
      payload.set('isAutoRotate', this.autoRotateEnabled());
      this.sink?.success(payload);
    } else {
      this.sink?.success(next);
    }
  }

  // 0 = 竖屏正立，±180 = 竖屏倒立，+90 = landscapeLeft，-90 = landscapeRight。
  private classify(theta: number): string {
    const centers: Record<string, number> = {
      'portraitUp': 0, 'landscapeLeft': 90, 'landscapeRight': -90, 'portraitDown': 180
    };
    const distance = (a: number, b: number): number => {
      const d = Math.abs(a - b) % 360;
      return d > 180 ? 360 - d : d;
    };
    if (this.current != null && distance(theta, centers[this.current]) < 45 + SWITCH_MARGIN) {
      return this.current;
    }
    let best = 'portraitUp';
    let bestDistance = 360;
    Object.keys(centers).forEach((name: string) => {
      const d = distance(theta, centers[name]);
      if (d < bestDistance) {
        bestDistance = d;
        best = name;
      }
    });
    return best;
  }
}
