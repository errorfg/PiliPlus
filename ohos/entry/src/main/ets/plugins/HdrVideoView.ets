// HDR 视频的画面层。Flutter 把纹理按 SDR 合成，HDR 只能在由系统直接合成的
// 图层上点亮：这里用平台视图放一个 XComponent，libmpv 直接渲染到它的 surface 上，
// 并给 surface 标上色彩空间与 HDR 元数据。需要引擎开启混合合成
// （buildinfo.json5 的 enable_ohos_hybrid_composition）。
import {
  Any,
  BinaryMessenger,
  Log,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  PlatformView,
  PlatformViewFactory,
  StandardMessageCodec
} from '@ohos/flutter_ohos';
import { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import { common } from '@kit.AbilityKit';

const TAG = 'HdrVideoView';

class HdrSurfaceController extends XComponentController {
  private view: HdrVideoView;

  constructor(view: HdrVideoView) {
    super();
    this.view = view;
  }

  onSurfaceCreated(surfaceId: string): void {
    this.view.surfaceId = surfaceId;
    this.view.notifySurface();
  }

  onSurfaceChanged(surfaceId: string, rect: SurfaceRect): void {
    this.view.surfaceId = surfaceId;
    this.view.surfaceWidth = rect.surfaceWidth;
    this.view.surfaceHeight = rect.surfaceHeight;
    this.view.notifySurface();
  }

  onSurfaceDestroyed(surfaceId: string): void {
    this.view.surfaceId = '';
    this.view.channel?.invokeMethod('onSurfaceDestroyed', null);
  }
}

@Component
struct HdrSurface {
  view: HdrVideoView | null = null;

  build() {
    XComponent({ type: XComponentType.SURFACE, controller: this.view!.controller })
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
      .hitTestBehavior(HitTestMode.None)
  }
}

@Builder
function hdrSurfaceBuilder(params: Params) {
  HdrSurface({ view: params.platformView as HdrVideoView })
}

export class HdrVideoView extends PlatformView implements MethodCallHandler {
  controller: HdrSurfaceController = new HdrSurfaceController(this);
  channel: MethodChannel | null = null;
  surfaceId: string = '';
  surfaceWidth: number = 0;
  surfaceHeight: number = 0;
  private dartReady = false;

  constructor(messenger: BinaryMessenger, viewId: number) {
    super();
    this.channel = new MethodChannel(messenger, `piliplus/hdr_video_${viewId}`);
    this.channel.setMethodCallHandler(this);
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'ready') {
      this.dartReady = true;
      this.notifySurface();
      result.success(null);
    } else {
      result.notImplemented();
    }
  }

  // surface 建好、尺寸已知、Dart 端也已开始监听之后才上报
  notifySurface(): void {
    if (!this.dartReady || this.surfaceId === '' || this.surfaceWidth <= 0 || this.surfaceHeight <= 0) {
      return;
    }
    const args = new Map<string, Object>();
    args.set('surfaceId', this.surfaceId);
    args.set('width', this.surfaceWidth);
    args.set('height', this.surfaceHeight);
    Log.i(TAG, `surface ${this.surfaceId} ${this.surfaceWidth}x${this.surfaceHeight}`);
    this.channel?.invokeMethod('onSurface', args);
  }

  getView(): WrappedBuilder<[Params]> {
    return wrapBuilder(hdrSurfaceBuilder);
  }

  dispose(): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }
}

export class HdrVideoViewFactory extends PlatformViewFactory {
  private messenger: BinaryMessenger;

  constructor(messenger: BinaryMessenger) {
    super(StandardMessageCodec.INSTANCE);
    this.messenger = messenger;
  }

  create(context: common.Context, viewId: number, args: Any): PlatformView {
    return new HdrVideoView(this.messenger, viewId);
  }
}
