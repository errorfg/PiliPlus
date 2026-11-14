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

const TAG = 'DeviceOrientationPlugin';
// 屏幕平面内的重力角偏离当前方向多少度才切换。竖横分界在 45°，两侧各留 20° 防抖。
const SWITCH_MARGIN = 20;
// 设备接近平放时重力在屏幕平面内的分量很小，方向不可靠，不上报。
const MIN_PLANAR_GRAVITY = 3.0;

export default class DeviceOrientationPlugin implements FlutterPlugin, MethodCallHandler, StreamHandler {
  private channel: MethodChannel | null = null;
  private eventChannel: EventChannel | null = null;
  private sink: EventSink | null = null;
  private listening = false;
  private withAutoRotate = false;
  private current: string | null = null;
  private onGravity = (data: sensor.GravityResponse): void => this.handle(data.x, data.y);

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
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
    if (this.withAutoRotate) {
      const payload = new Map<string, Object>();
      payload.set('orientation', next);
      payload.set('isAutoRotate', true);
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
