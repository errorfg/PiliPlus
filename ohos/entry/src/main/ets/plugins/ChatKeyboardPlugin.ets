// 聊天输入面板：实现 chat_bottom_container 的键盘高度上报。
// Dart 端由 pigeon 生成，要求收到的是 [double]；嵌入层的标准编码会把整数值的
// number 编成 int，Dart 端转换失败，所以这里按标准消息编码手工写出字节。
import {
  AbilityAware,
  AbilityPluginBinding,
  BinaryMessenger,
  FlutterPlugin,
  FlutterPluginBinding,
  Log
} from '@ohos/flutter_ohos';
import { display, window } from '@kit.ArkUI';

const TAG = 'ChatKeyboardPlugin';
const CHANNEL =
  'dev.flutter.pigeon.chat_bottom_container.FSAChatBottomContainerFlutterApi.keyboardHeight';

export default class ChatKeyboardPlugin implements FlutterPlugin, AbilityAware {
  private messenger: BinaryMessenger | null = null;
  private win: window.Window | null = null;
  private onKeyboardHeight = (px: number): void => this.send(px);

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.messenger = binding.getBinaryMessenger();
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.messenger = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    window.getLastWindow(binding.getAbility().context).then((win: window.Window) => {
      this.win = win;
      win.on('keyboardHeightChange', this.onKeyboardHeight);
    }).catch((e: Error) => {
      Log.e(TAG, `getLastWindow failed: ${JSON.stringify(e)}`);
    });
  }

  onDetachedFromAbility(): void {
    try {
      this.win?.off('keyboardHeightChange', this.onKeyboardHeight);
    } catch (e) {
      Log.e(TAG, `off keyboardHeightChange failed: ${JSON.stringify(e)}`);
    }
    this.win = null;
  }

  // 系统给的是物理像素，Dart 端要逻辑像素。
  private send(px: number): void {
    let density = 1;
    try {
      density = display.getDefaultDisplaySync().densityPixels;
    } catch (e) {
      Log.e(TAG, `read display density failed: ${JSON.stringify(e)}`);
    }
    // 标准消息编码：列表(0x0C) 长度 1，元素为 float64(0x06)，数据按 8 字节对齐。
    const buffer = new ArrayBuffer(16);
    const view = new DataView(buffer);
    view.setUint8(0, 0x0C);
    view.setUint8(1, 1);
    view.setUint8(2, 0x06);
    view.setFloat64(8, px / density, true);
    this.messenger?.send(CHANNEL, buffer);
  }
}
