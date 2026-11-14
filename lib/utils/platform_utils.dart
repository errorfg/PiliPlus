import 'dart:io' show Platform;

abstract final class PlatformUtils {
  /// 官方 Flutter 的 dart:io 没有 `Platform.isOhos`，只能比较字符串。
  @pragma("vm:platform-const")
  static final bool isOhos = Platform.operatingSystem == 'ohos';

  @pragma("vm:platform-const")
  static final bool isMobile = Platform.isAndroid || Platform.isIOS || isOhos;

  @pragma("vm:platform-const")
  static final bool isDesktop =
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @pragma("vm:platform-const")
  static final bool isDarwin = Platform.isIOS || Platform.isMacOS;
}
