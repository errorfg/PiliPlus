# iOS 上的 HDR 直出

> 阅读前注意：这份文档里的每一条，凡是没有标明「实测」「用户确认」或「读源码得到」的，都只是我的推断。2026-11-15 做过一次整体审查，把原先写成事实的推断改成了推断，并删除了没有依据的说法。屏幕上会动的现象（何时出现、是否闪烁、亮不亮）一律以用户的描述为准，我看不了视频，单张截图不能代表过程。

## 问题

iOS 上播放器（media_kit + libmpv）用 OpenGL ES 把画面渲染进一张 8 位 BGRA 的 Flutter 纹理，Flutter 把纹理按 SDR 合成。libmpv 构建里的 FFmpeg 补丁 `ffmpeg-fix-ios-hdr-texture.patch` 还让 10 位视频在 VideoToolbox 解码时就输出 8 位 BGRA（原因是 iOS 的 GLES 不支持 10 位纹理）。因此 PQ、HLG 视频只能经色调映射显示为 SDR。

## 做法

与鸿蒙相同的思路（见 `harmony-port.md` 3.12 节）：HDR 视频不经过 Flutter 纹理，解码器输出的画面直接交给系统合成的图层。

1. **libmpv**：给 mpv 0.39.0 增加视频输出 `avfoundation`（`video/out/vo_avfoundation.m`）。它只接收 VideoToolbox 的硬件帧，把帧里的 `CVPixelBuffer` 包成 `CMSampleBuffer`，送进由 `--wid` 传入地址的 `AVSampleBufferDisplayLayer`，缺失的色彩标记按 mpv 的参数补上。mpv 在这条路径上不做任何渲染。上游 mpv 的 0.39、0.40、0.41 和 master 里没有 `video/out/vo_avfoundation.m` 这个文件（只查了这一个文件名，是否有别的名字的同类输出没有查）。
2. **解码格式**：FFmpeg 的补丁不改。走这条路径时设置 mpv 选项 `hwdec-image-format=p010`，让解码器输出 10 位；回到纹理时设回 `no`。
3. **原生端**：`ios/Runner/HdrVideoView.swift` 注册平台视图 `piliplus/hdr_video`，视图的图层就是 `AVSampleBufferDisplayLayer`；通道 `piliplus/hdr_video_<id>` 的 `layer` 方法返回图层地址。
4. **Dart 端**：`lib/utils/ios/hdr_output.dart`。
   - `IosHdrOutput` 监听视频参数；解码侧的 `video-params/gamma` 是 `pq` 或 `hlg`、且 `hwdec-current` 是 VideoToolbox 时，置 `active`。
   - `IosHdrVideo` 在 `active` 时把平台视图盖在纹理上（`pl_player/view/view.dart` 里包住 `SimpleVideo`），视图尺寸与纹理相同，缩放、翻转由 Flutter 的变换完成。
   - 视图创建后取得图层地址，切换输出：`wid`、`hwdec-image-format=p010`、`vo=avfoundation`；离开时切回 `vo=libmpv`。
5. **开关**：设置项「HDR 直出」（`Pref.hdrDirectOutput`，默认开），iOS 与鸿蒙共用。

## 实现中的记录

- **切换输出时关开视频轨。** 实测：不这样做时，从中途续播的视频切到 `avfoundation` 后 `hwdec-current` 变成 `no`、像素格式是 `yuv420p10`（两次）；从头播放的那一次正常。改成切换前把 `vid` 设为 `no`、改完选项再设回原值（`IosHdrOutput._switchOutput`）之后，日志里的几次切换都是硬件解码、`p010`。「mpv 在 `vo` 变化时保留已有的解码器」是我对这个现象的解释，没有在 mpv 源码里核对。
- **判断是否点亮的客观指标**：`UIScreen.currentEDRHeadroom`。iPhone Duo 上播放 4K HDR（HEVC，PQ，BT.2020，60 帧）时，切换前为 1.2，切换后为 8.0（`potentialEDRHeadroom` 为 8.0），图层状态为正在渲染，那几秒里丢帧 0（实测，日志只覆盖播放的最初几秒到几十秒）。用户的目视结论（2026-11-15）：第一个包「没有点亮，只是色调映射」，与日志里那次切换失败对应；修正后「看起来差不多了」；再后来说某一版「才是真正的 HDR」，随后解释是因为那一段是大片白色所以显得很亮。

## 画中画

HDR 视频不在纹理里，原有的画中画（`PipPlugin.swift` 从纹理拷贝帧到自己的图层）拿不到画面。做法是让 HDR 平台视图的图层本身作为画中画的内容来源：

- Dart 端进入或登记画中画时带上 `hdrViewId`（`IosHdrOutput.viewId`）；画面在纹理和 HDR 图层之间切换时，后台自动画中画按新的来源重新登记（`PlPlayerController._onIosHdrViewChanged`）。
- 原生端按 `hdrViewId` 找到图层，用它创建 `AVPictureInPictureController`，不再拷贝帧。进入、退出画中画都不切换 mpv 的输出。用户确认小窗里是 HDR（「现在确实都是 HDR 了」）；「返回时不再重新加载」用户没有再提，也没有明确确认。
- `vo_avfoundation` 用图层的 `controlTimebase` 的当前时间给帧打时间戳（画中画用这个时钟显示进度）。
- **登记时机（推断，证据很少）**：现在的代码等 HDR 图层已在屏幕上并正在显示画面后才创建会话（`PipPlugin.enter` 每 0.1 秒重试，最多 5 秒）。实测记录只有：改之前两次运行里，第一次退到后台都没有进入画中画、第二次进入，当时系统报告的「可以进入」「允许自动进入」都为真；改之后日志里有一次 HDR 视频第一次退到后台就进入了。「图层没有画面时创建控制器会导致第一次不启动」是我的推断，一次成功不足以证明。用户在这之后没有明确确认 HDR 视频第一次必定弹出小窗。日志里还有一次普通视频（纹理路径）第三次退到后台没有进入，原因不明。
- **返回时的画面（推断，未验证）**：用户报告从小窗回到视频时会闪一下黑。我的推断是画中画期间图层的内容显示在小窗里、原位置是空的，据此加了处理：回到应用时在原位置叠一个同步显示的图层（`HdrVideoViewFactory.setMirroring`，`vo_avfoundation` 读图层上键为 `mpvMirrorLayer` 的值，把每一帧同时送给它），小窗归位 0.3 秒后撤掉。这个推断没有验证过，加了处理之后是否还闪，用户没有反馈。
- 缓冲状态变化时也向原生端更新播放状态（`stream.buffering` 监听里调用 `_updateIOSPip`）。这是为「第一次不弹小窗」加的，依据是读代码：登记时若处于缓冲，时钟速率被设为 0，之后只有特定事件才更新。但实测否定了它是那个问题的原因（失败的那次时钟速率是 1.0）。这处改动留着，没有观察到它解决过任何问题。

## 限制与未解决的问题

- 直出时 mpv 不渲染，着色器不生效；截图是否可用未验证。
- 软件解码的 HDR 视频不走这条路径。
- **小窗与正片有亮度差别（现象，原因不明）**：用户观察到画中画小窗里的画面比应用内播放时暗。是本程序的问题还是别的原因，不清楚。
- **灵动岛在前台出现（未解决，与 HDR 无关）**：一开始播放，系统的「正在播放」就出现在灵动岛里，应用仍在前台；退到后台进小窗后两者并存。用户用调试包把 HDR 直出、关开视频轨、图层、输出切换、画中画全部关掉后现象不变。
  - 用户用旧包确认：旧包同样有这个现象，不是 2026-11-15 的代码引入的。用调试面板把 HDR 的各个步骤全部关掉、把 `audio_service` 登记的媒体类型从音频改成视频，都没有区别。
  - **最小复现（2026-11-15，实测）**：一个约 200 行、只用系统标准接口的原生应用（本机 `piliplus-local-build/nowplaying-test/`，不含 Flutter、libmpv、视频、画中画，Info.plist 里没有后台播放能力），用与 PiliPlus 相同的方式签名后装到同一台手机。它在前台时，边条里出现「正在播放」。应用自动轮换各个条件，每个阶段末尾截一张图，结果：
    - 出现：四项齐备时（出声音、音频会话独占、登记远程命令、发布正在播放信息）。把媒体类型改成视频、不设 `playbackState`、不用 `moviePlayback` 模式、调用 `beginReceivingRemoteControlEvents`，都不改变结果。
    - 不出现：四项中任意一项关闭（不出声音、会话改为可混音、不登记远程命令、不发布信息），以及全部停止时。
    - 这是每个阶段一张静止截图的结果，只跑了一轮，最后一个阶段的截图处于过渡状态。是否与用户肉眼看到的一致，尚未请用户确认。
    - 它说明现象与 PiliPlus 的代码无关。它本身不能说明原因是签名，因为缺少「同一个应用、权限里写实际包名」的对照。
  - **调研（子智能体做的网络调研，来源我没有逐条复核）**：
    - 同一现象在多种重签名方式下都有人报告。上游 PiliPlus 的 #3108 写道：只有用 p12 证书签名的包才有，自签名的版本没有。另有报告称改用 AltStore、SideStore 后消失，或把包名改成与证书的应用标识一致后消失。
    - 一份第三方反编译的 iOS 26.1 固件显示，`mediaremoted` 从进程的 `application-identifier` 权限取包名：去掉前面的团队标识后，余下部分当作包名。权限是 `<团队>.*` 时得到的就是 `*`。这与本机系统日志里 PiliPlus 被记为 `* (pid)` 相符。固件版本不是 27.2。
    - Xcode 导出时会把通配符换成实际包名；fastlane 的 `sigh resign`、zsign 在未指定权限时保留通配符。本项目的签名服务是把描述文件里的权限原样写入。
    - 没有找到系统「前台时隐藏正在播放」的判定逻辑的公开说明，也没有找到正常签名的应用出现同样现象的报告。
  - 现状：有间接证据指向「权限里的应用标识与包名不一致」，但因果没有被直接验证。直接验证的办法是对照实验：同一个最小应用，权限里写实际包名，看前台是否还出现。
  - 读设备系统日志的方法：`idevicesyslog -u <UDID> -n`。
- **进入 HDR 视频时黑屏约 3 秒（未解决）**：依据是用户录屏的抽帧（每秒 2 帧，封面之后有约 7 帧全黑）。原因是我读代码的推断，没有验证：`active` 一置位就把黑色的平台视图盖在纹理上，而画面要等输出切换、解码器重建后才到。
- 返回时闪黑的处理和第一次自动进入的修复，各只有一次实测记录。

## 构建（只在本机）

libmpv 不在仓库里，在 `piliplus-local-build/`：

- `libmpv-build/`：iOS 整套 libmpv 的源码构建，说明见其中的 `LOCAL_BUILD.md`。mpv 的补丁是 `patches/mpv-vo-avfoundation.patch`，由 `scripts/mpv/build.sh` 在 iOS 的 video 变体上应用。
- 只重编 mpv：删除 `build/intermediate/mpv_ios-arm64-video` 后执行 `make build/intermediate/frameworks_ios-arm64-video-default`（PATH 里 `/usr/bin` 在前）。
- `tools/pack_libmpv_ios.sh`：把上游发布包里 ios-arm64 的 Avcodec（AV1 硬解）和 Mpv（含 `avfoundation` 输出）换成本机构建的，打包并更新 `media_kit_libs_ios_video` 的版本与校验值。
- `tools/build_ios.sh <提交>`：出包。
- 诊断：`tools/diag_hdr.py`（每 2 秒把 mpv 的输出状态和屏幕亮度余量写到标准错误）、`tools/rebuild_wt_ios.sh`（重建并签名实验包）；用 `devicectl device process launch --console` 读取。发布版的 `print` 不进这个控制台，要写 `stderr`。

用官方发布的 libmpv 构建（例如 CI）时没有 `avfoundation` 输出。这种情况下会发生什么没有测过；按代码推断，切换输出的设置不生效，而 `hwdec-image-format=p010` 仍会生效，HDR 视频可能退回软件解码。代码里没有对此做检测。
