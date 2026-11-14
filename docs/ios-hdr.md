# iOS 上的 HDR 直出

## 问题

iOS 上播放器（media_kit + libmpv）用 OpenGL ES 把画面渲染进一张 8 位 BGRA 的 Flutter 纹理，Flutter 把纹理按 SDR 合成。libmpv 构建里的 FFmpeg 补丁 `ffmpeg-fix-ios-hdr-texture.patch` 还让 10 位视频在 VideoToolbox 解码时就输出 8 位 BGRA（原因是 iOS 的 GLES 不支持 10 位纹理）。因此 PQ、HLG 视频只能经色调映射显示为 SDR。

## 做法

与鸿蒙相同的思路（见 `harmony-port.md` 3.12 节）：HDR 视频不经过 Flutter 纹理，解码器输出的画面直接交给系统合成的图层。

1. **libmpv**：给 mpv 0.39.0 增加视频输出 `avfoundation`（`video/out/vo_avfoundation.m`）。它只接收 VideoToolbox 的硬件帧，把帧里的 `CVPixelBuffer` 包成 `CMSampleBuffer`，送进由 `--wid` 传入地址的 `AVSampleBufferDisplayLayer`，缺失的色彩标记按 mpv 的参数补上。mpv 在这条路径上不做任何渲染。上游 mpv（0.39、0.40、0.41、master）没有这样的输出。
2. **解码格式**：FFmpeg 的补丁不改。走这条路径时设置 mpv 选项 `hwdec-image-format=p010`，让解码器输出 10 位；回到纹理时设回 `no`。
3. **原生端**：`ios/Runner/HdrVideoView.swift` 注册平台视图 `piliplus/hdr_video`，视图的图层就是 `AVSampleBufferDisplayLayer`；通道 `piliplus/hdr_video_<id>` 的 `layer` 方法返回图层地址。
4. **Dart 端**：`lib/utils/ios/hdr_output.dart`。
   - `IosHdrOutput` 监听视频参数；解码侧的 `video-params/gamma` 是 `pq` 或 `hlg`、且 `hwdec-current` 是 VideoToolbox 时，置 `active`。
   - `IosHdrVideo` 在 `active` 时把平台视图盖在纹理上（`pl_player/view/view.dart` 里包住 `SimpleVideo`），视图尺寸与纹理相同，缩放、翻转由 Flutter 的变换完成。
   - 视图创建后取得图层地址，切换输出：`wid`、`hwdec-image-format=p010`、`vo=avfoundation`；离开时切回 `vo=libmpv`。
5. **开关**：设置项「HDR 直出」（`Pref.hdrDirectOutput`，默认开），iOS 与鸿蒙共用。

## 实现中确认的事实

- **切换输出必须重建解码器。** mpv 在 `vo` 变化时保留已有的解码器。纹理路径的解码器输出 8 位 BGRA，直出路径需要 10 位硬件帧；若不重建，切到 `avfoundation` 后拿到的是不被接收的帧，解码退回软解。做法是切换前把 `vid` 设为 `no`，改完选项再设回原值（`IosHdrOutput._switchOutput`）。
- **判断是否点亮的客观指标**：`UIScreen.currentEDRHeadroom`。iPhone Duo 上播放 4K HDR（HEVC，PQ，BT.2020，60 帧）时，切换前为 1.2，切换后为 8.0（`potentialEDRHeadroom` 为 8.0），图层状态为正在渲染，丢帧 0。用户目视确认点亮（2026-11-15）。
- 屏幕的「降低白点值」和低电量模式会压低亮度，判断效果前要确认都关闭。

## 限制

- 画中画的画面取自纹理（`PipPlugin.swift` 从纹理拷贝帧）。进入画中画时 HDR 视频退回纹理（`IosHdrOutput.suspended`），小窗里是色调映射后的画面，退出后恢复。后台自动进入画中画的情形未验证。
- 直出时 mpv 不渲染，着色器不生效；截图是否可用未验证。
- 软件解码的 HDR 视频不走这条路径。

## 构建（只在本机）

libmpv 不在仓库里，在 `piliplus-local-build/`：

- `libmpv-build/`：iOS 整套 libmpv 的源码构建，说明见其中的 `LOCAL_BUILD.md`。mpv 的补丁是 `patches/mpv-vo-avfoundation.patch`，由 `scripts/mpv/build.sh` 在 iOS 的 video 变体上应用。
- 只重编 mpv：删除 `build/intermediate/mpv_ios-arm64-video` 后执行 `make build/intermediate/frameworks_ios-arm64-video-default`（PATH 里 `/usr/bin` 在前）。
- `tools/pack_libmpv_ios.sh`：把上游发布包里 ios-arm64 的 Avcodec（AV1 硬解）和 Mpv（含 `avfoundation` 输出）换成本机构建的，打包并更新 `media_kit_libs_ios_video` 的版本与校验值。
- `tools/build_ios.sh <提交>`：出包。
- 诊断：`tools/diag_hdr.py`（每 2 秒把 mpv 的输出状态和屏幕亮度余量写到标准错误）、`tools/rebuild_wt_ios.sh`（重建并签名实验包）；用 `devicectl device process launch --console` 读取。发布版的 `print` 不进这个控制台，要写 `stderr`。

用官方发布的 libmpv 构建（例如 CI）时没有 `avfoundation` 输出：切换输出的设置不生效，而 `hwdec-image-format=p010` 仍会生效，纹理路径无法使用 10 位硬件帧，HDR 视频会退回软件解码。这样的包应关闭「HDR 直出」。代码里没有对此做检测。
