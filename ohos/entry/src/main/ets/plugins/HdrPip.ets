// HDR 视频的画中画：把 HDR 画面层（HdrVideoView 里的 XComponent）直接交给系统。
// 系统把这一层挪进小窗，解码器照常直接送显，HDR 保持点亮；小窗里只有视频，
// 没有 Flutter 画的弹幕和字幕。普通视频的画中画走 floating 插件，不经过这里。
import { Log, MethodChannel } from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { PiPWindow } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { HdrVideoView } from './HdrVideoView';

const TAG = 'HdrPip';

export class HdrPip {
  static channel: MethodChannel | null = null;
  static context: common.UIAbilityContext | null = null;
  private static controller: PiPWindow.PiPController | null = null;
  private static owner: HdrVideoView | null = null;
  private static autoStart = false;

  // 画中画控制器绑定在某一个画面层上；画面层换了（换了视频）就重建。
  private static async ensure(width: number, height: number): Promise<PiPWindow.PiPController | null> {
    const view = HdrVideoView.active;
    const context = HdrPip.context;
    if (view == null || context == null || !PiPWindow.isPiPEnabled()) {
      return null;
    }
    if (HdrPip.controller != null && HdrPip.owner === view) {
      HdrPip.controller.updateContentSize(width, height);
      return HdrPip.controller;
    }
    await HdrPip.release();
    const controller = await PiPWindow.create({
      context: context,
      componentController: view.controller,
      templateType: PiPWindow.PiPTemplateType.VIDEO_PLAY,
      contentWidth: width,
      contentHeight: height,
      controlGroups: [PiPWindow.VideoPlayControlGroup.FAST_FORWARD_BACKWARD]
    });
    controller.on('stateChange', (state: PiPWindow.PiPState, reason: string) => {
      Log.i(TAG, `state ${state} ${reason}`);
      if (state === PiPWindow.PiPState.STARTED) {
        HdrPip.channel?.invokeMethod('onHdrPipState', true);
      } else if (state === PiPWindow.PiPState.STOPPED || state === PiPWindow.PiPState.ERROR) {
        HdrPip.channel?.invokeMethod('onHdrPipState', false);
      }
    });
    controller.on('controlPanelActionEvent', (event: PiPWindow.PiPActionEventType, status?: number) => {
      const args = new Map<string, Object>();
      args.set('event', event as string);
      if (status !== undefined) {
        args.set('status', status);
      }
      HdrPip.channel?.invokeMethod('onHdrPipAction', args);
    });
    controller.setAutoStartEnabled(HdrPip.autoStart);
    HdrPip.controller = controller;
    HdrPip.owner = view;
    return controller;
  }

  // 立即进入画中画，然后把应用退到后台（与安卓上点画中画按钮的效果一致）。
  static async start(width: number, height: number): Promise<boolean> {
    try {
      const controller = await HdrPip.ensure(width, height);
      if (controller == null) {
        return false;
      }
      await controller.startPiP();
      HdrPip.context?.moveAbilityToBackground().catch((e: BusinessError) => {
        Log.e(TAG, `moveAbilityToBackground failed: ${e.code}`);
      });
      return true;
    } catch (e) {
      Log.e(TAG, `start failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  // 让系统在应用退到后台时自动进入画中画。
  static async setAutoStart(enable: boolean, width: number, height: number): Promise<boolean> {
    HdrPip.autoStart = enable;
    try {
      if (enable) {
        return (await HdrPip.ensure(width, height)) != null;
      }
      HdrPip.controller?.setAutoStartEnabled(false);
      return true;
    } catch (e) {
      Log.e(TAG, `setAutoStart failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  static updatePlaying(playing: boolean): void {
    try {
      HdrPip.controller?.updatePiPControlStatus(PiPWindow.PiPControlType.VIDEO_PLAY_PAUSE,
        playing ? PiPWindow.PiPControlStatus.PLAY : PiPWindow.PiPControlStatus.PAUSE);
    } catch (e) {
      Log.e(TAG, `updatePiPControlStatus failed: ${JSON.stringify(e)}`);
    }
  }

  static async stop(): Promise<void> {
    try {
      await HdrPip.controller?.stopPiP();
    } catch (e) {
      Log.e(TAG, `stopPiP failed: ${JSON.stringify(e)}`);
    }
  }

  // 画面层销毁或换了视频时调用。
  static async release(): Promise<void> {
    const controller = HdrPip.controller;
    HdrPip.controller = null;
    HdrPip.owner = null;
    if (controller == null) {
      return;
    }
    try {
      controller.setAutoStartEnabled(false);
      controller.off('stateChange');
      controller.off('controlPanelActionEvent');
      await controller.stopPiP();
    } catch (e) {
      // 没有在画中画里时 stopPiP 会报错，可以忽略
    }
  }

  static onViewDisposed(view: HdrVideoView): void {
    if (HdrPip.owner === view) {
      HdrPip.release();
    }
  }
}
