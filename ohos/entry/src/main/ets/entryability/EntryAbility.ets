import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import DeviceOrientationPlugin from '../plugins/DeviceOrientationPlugin';
import ScreenBrightnessPlugin from '../plugins/ScreenBrightnessPlugin';

export default class EntryAbility extends FlutterAbility {
  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // 没有现成鸿蒙实现的插件，在宿主里按 Dart 端的通道协议实现
    flutterEngine.getPlugins()?.add(new DeviceOrientationPlugin())
    flutterEngine.getPlugins()?.add(new ScreenBrightnessPlugin())
  }
}
