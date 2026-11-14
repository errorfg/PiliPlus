# 鸿蒙移植记录

这份文档记录鸿蒙版的技术决策、从其他移植工作里观察到的做法、已知的妥协和尚未验证的事项。每完成一段工作就更新，目的是让后来的人（包括上下文被压缩后的我自己）不必重新推导。

## 1. 原则

- 基线是上游 PiliPlus（当前 2.2.1），鸿蒙改动放在 `feature/harmony`，叠在 `feature/iphone-duo` 之上。
- 本仓库同时出 iOS、安卓和鸿蒙的包。共用代码必须能用官方 Flutter 编译，鸿蒙专属的东西按平台隔离。
- 其他人的鸿蒙移植只作参考：技术选型可以借鉴，设计按「怎样合理」来定，不以与它一致为目标。
- 不移植短视频模式（用户决定）。包名 `com.errorfg.piliplus`。

## 2. 观察到的做法

### 2.1 `2751833085/PiliPlus-Harmony`（Beta 1.2）

- 基线：上游 2.1.4 → dev4harmony 的 `ohos` 分支 → 作者自己的 204 个提交。相对 2.1.4 改了 919 个文件。
- 工具链：Flutter OpenHarmony 3.44.9。上游已改用 pub 上的 `material_ui`、`cupertino_ui`，它用仓库内的转接包把这两个包映射回 SDK 内置实现；上游打在 SDK 上的补丁则以组件副本（约 9200 行）的形式放进 `lib/common/widgets/flutter/`。
- 直接修改共用页面（如 `pages/video/view.dart` 改 2233 行），并删除了其他平台的 CI，等于只面向鸿蒙。
- 导航：`Pref.harmonyUI` 恒为真，侧栏恒关闭，宽窗口也用底栏。API 23 及以上，底栏和首页顶栏由 ArkTS 画在 Flutter 画面之上（`Index.ets`），Flutter 只留占位，显隐靠桥接通道同步；作者的修复提交多集中在这套同步上。
- 取色：去掉了 Material You。
- 播放器：`cnoim/media-kit` 的 `feat-ohos` 分支，加上作者重新编译的 `libmpv.so`（开启全部 FFmpeg 滤镜和 AV3A）。
- 画中画：`qinshah/floating` 的鸿蒙实现，把 Flutter 引擎的输出切到画中画窗口。
- 其他系统集成：后台播放、接续、桌面卡片、动态照片保存、折叠姿态。
- 作者自述多数业务功能未在真机验证，模拟器没有视频输出。

### 2.2 `dev4harmony/PiliPlus` 的 `ohos` 分支

- 仍在维护，同步到上游 2.1.6，同样用 3.44.9 加转接包。上面那个仓库的宿主工程、桥接通道、原生顶栏底栏都继承自这里。

### 2.3 CPF-Flutter（gitcode）的插件仓库

- `flutter_flutter` 有 `oh-3.47.7-dev` 分支；`flutter_packages` 有同名分支；plus 系列、audio_service、audio_session、wakelock_plus、app_links、file_picker 有 `br_3.41_dev` 或对应版本的开发分支。
- 这些分支的质量不一，下面第 5 节列了遇到的缺陷。

## 3. 技术决策

### 3.1 工具链：Flutter OpenHarmony 3.47.7，不走 3.44.9 加转接包

- 实测 `oh-3.47.7-dev` 能解析上游 2.2.1 的全部依赖并出包。这样不需要转接包，也不需要 9200 行组件副本。
- 代价：这是开发分支，比上游要求的 3.47.9 低两个补丁版本。上游 26 个 SDK 补丁里 22 个直接可用，4 个（text_selection、selectable_region、scrollable_gesture、navigator，共 6 处）要维护鸿蒙版本。
- pub 上的 `material_ui`、`cupertino_ui` 不认识鸿蒙平台，有 84 处平台分支要补。先按「与安卓同组」填写，再用脚本逐文件对照 Flutter OH 自带的 material、cupertino 里鸿蒙所在的分组：cupertino 的 11 个文件全部一致；material 有 10 个文件不同，其中影响行为的已改成与 Flutter OH 一致——点状态栏回到顶部（与 iOS 同组）、滚动条不用安卓样式、抽屉不按「系统有返回键」处理、日期选择不振动、下拉菜单选择后收起焦点、字体排版归入 Linux 组。
- 仍与 Flutter OH 不同的 4 处只涉及无障碍朗读和 `AlertDialog` 默认可滚动，没有改。Flutter OH 给鸿蒙用的默认转场 `OpenRightwardsPageTransitionsBuilder` 在 pub 包里不存在，鸿蒙回落到缩放转场。

### 3.2 `TargetPlatform.ohos` 不进共用代码

- 官方 Flutter 没有这个枚举值，写进 `lib/` 会让其他平台编译失败。
- `lib/` 里需要它的 43 处分支存为 `ohos/patches/lib-target-platform.patch`，只在鸿蒙构建时应用。
- 共用代码里判断鸿蒙一律用 `PlatformUtils.isOhos`（比较 `Platform.operatingSystem`）。`PlatformUtils.isMobile` 已包含鸿蒙。

### 3.3 鸿蒙专属依赖放在 `ohos/pubspec_ohos.yaml`

- 构建时并入 `pubspec.yaml`，其他平台不读它。
- `dependencies`：只含鸿蒙实现的包（如 `path_provider_ohos`），面向应用的包仍用 `pubspec.yaml` 里的版本。
- `dependency_overrides`：鸿蒙实现写在面向应用的包里的，整包换成鸿蒙分支。
- 共用的 Dart 代码不能 `import` 只在这个文件里出现的包。需要它的原生部分时，Dart 端自己走方法通道（画中画就是这样）。

### 3.4 小插件直接写在宿主里

没有可用鸿蒙实现、协议又简单的插件，在 `ohos/entry/src/main/ets/plugins/` 里按 Dart 端的通道协议实现，由 `EntryAbility` 注册：

- `DeviceOrientationPlugin`：上游 `native_device_orientation` 分叉的协议。用重力传感器判断方向；三折叠全部展开时把传感器方向换算成屏幕方向；读系统的自动旋转开关。
- `ScreenBrightnessPlugin`：`screen_brightness_platform_interface` 的协议。鸿蒙不允许普通应用改系统亮度，读写都落在窗口亮度上。
- `ChatKeyboardPlugin`：`chat_bottom_container` 的键盘高度上报。嵌入层的标准编码把整数值的 number 编成 int，而 Dart 端要 double，所以手工写出消息字节。

### 3.5 播放器：把鸿蒙支持移植到上游用的 media_kit 分支上

- 没有整体换成 `cnoim/media-kit`。上游用的是自己的 `native` 分支（结构已精简），整体替换会让播放器代码与上游分叉。
- 移植的内容约 700 行：加载 `libmpv.so`、鸿蒙走 isolate 事件循环（没有 native event loop 的鸿蒙构建）、`OhosVideoController`、ArkTS 的纹理插件。
- `libmpv.so` 用的是 2.1 那个仓库作者重新编译的二进制，没有自行从源码编译。
- 实测（Mate XTs，1080p30）：H.264 与 HEVC 走 ohcodec 硬解、零拷贝、不丢帧；AV1 只有 dav1d 软解，处理器占用约为硬解的 3 倍。库里没有 VP9，也没有 AV1 硬解。
- 因此鸿蒙的默认首选编码是 AVC、HEVC（其他平台是 AVC、AV1）。

### 3.6 不提供动态取色

- CPF 的 `dynamic_color` 鸿蒙实现按壁纸颜色线性推算色阶，不是 Material 的色调算法，整套配色发灰。
- 鸿蒙与 iOS 一样只用所选主题色，设置项不显示，插件已移除。
- 如果以后要跟随壁纸：在宿主里读壁纸主色，再用 Material 的算法生成配色。

### 3.7 画中画：`floating` 的鸿蒙原生部分加自己的 Dart 封装

- 原生部分把 Flutter 引擎的输出切到画中画窗口里，页面此时只画播放器，与上游安卓画中画的页面逻辑相同，所以接入点可以共用（`PlPlayerController.systemPipMode`）。
- Dart 端是 `lib/utils/ohos/ohos_pip.dart`，原因见 3.3 最后一条。

### 3.8 折叠屏

- 窗口在手机大小与平板大小之间切换时，按当前的「横屏适配」重新设定方向限制（`main.dart` 的 `_WindowClassObserver`）。否则折叠态启动时锁定的竖屏会带到展开的屏幕上。这处在共用代码里，对安卓折叠屏和 iPhone Duo 也生效。
- 折叠态下主界面固定竖屏，只有视频页横过来进全屏（用户要求）。
- 底栏：鸿蒙上 `NavigationBar` 高度 56。默认的 80 叠在约 32 的导航条避让区上，留白过多。

### 3.9 其他按平台处理的行为

- 媒体控件：宿主声明 `backgroundModes: ["audioPlayback"]` 与 `KEEP_BACKGROUND_RUNNING`。缺少时 `audio_service` 申请长时任务失败，播放状态不上报。
- 保存图片：不申请相册权限。`saver_gallery` 的鸿蒙实现走系统的确认弹窗，而相册权限是受限权限。
- 主界面返回键：`SystemNavigator.pop()`，应用退到后台。
- 音量均衡：启用（`libmpv` 含 loudnorm、dynaudnorm）。
- 自动检查更新：关闭（上游没有鸿蒙安装包）。
- 亮度复位、自动旋转开关、全屏方向：与安卓走同一分支。

### 3.10 应用链接

- `module.json5` 声明了 `bilibili://` 和 B 站几个域名的网页链接。应用内的分发沿用上游的 `PiliScheme`（`app_links` 的鸿蒙实现）。
- 网页链接在鸿蒙上要做域名校验才会直接跳到应用，这里只是声明，实际能否从浏览器唤起没有验证。
- 这也是测试手段：`aa start -U 'bilibili://video/170001' -A ohos.want.action.viewData -e entity.system.browsable -b com.errorfg.piliplus` 可以直接打开指定页面，不必自动点击。

### 3.11 应用自己的桥接通道与动态照片

- 通道名 `piliplus/ohos`，原生端 `OhosBridgePlugin`，Dart 端 `lib/utils/ohos/ohos_bridge.dart`。需要宿主配合、又不属于某个现成插件的功能都走它。
- 保存动态照片：写入图库要相册权限，普通应用申请不到。做法是先准备好静态图（转成 JPEG）和视频，再在 `Index.ets` 弹出带系统安全控件 `SaveButton` 的确认层，用户点击后在临时授权内用 `MediaAssetChangeRequest` 写入。这个做法取自 2.1 的仓库。
- 普通图片和视频的保存不走这里，仍用 `saver_gallery`（系统的保存确认弹窗）。

### 3.12 HDR

现状（2026-11-14 深夜）：HDR 视频由硬件解码器直接送显到系统合成的画面层（设置里「HDR 直出」，默认开）。渲染服务一侧的证据：视频层的缓冲区是 P010、带 HDR10 元数据，屏幕的合成缓冲区从 8 位 sRGB 变成了 10 位广色域。用户在真机上确认 HDR 已点亮（2026-11-15）。关闭开关后 HDR 色调映射为 SDR，颜色正确。

事实：

- Flutter 把外接纹理按 SDR、sRGB 合成。libmpv 的目标色彩空间不指定时会跟随片源，把 PQ/BT.2020 的画面写进纹理，结果发灰。所以纹理路径上固定 `target-prim=bt.709`、`target-trc=bt.1886`、`tone-mapping=spline`、`target-colorspace-hint=no`（移植播放器时漏掉了这组设置，cnoim 的分叉里有）。
- 要点亮 HDR，画面必须在由系统直接合成的图层上。Flutter OH 3.47 的引擎有混合合成模式（`buildinfo.json5` 里 `enable_ohos_hybrid_composition`，已开启）：用 `PlatformViewsService.initExpensiveOhosView` 创建的平台视图是真正的系统图层，Flutter 的内容分成下层和透明的上层画在它两侧。实测开启后应用显示正常，渲染树里能看到 `oh_flutter_1Surface`、平台视图的 surface、`oh_flutter_1__overlaySurface` 三层。
- 已实现的切换机制：宿主的 `HdrVideoView`（平台视图里一个 `XComponent`）；播放器补丁里 `OhosVideoController` 在片源是 PQ/HLG 且允许时让视频控件改用这个平台视图，把 libmpv 的 `wid` 切到它的 surface，离开时切回纹理。判断片源要读解码侧的 `video-params/gamma`：输出侧的参数在重建视频输出时会短暂变成占位的 sRGB，surface 尺寸变化也不能触发重建，否则会循环。
- 这套机制本身工作正常（位置、控制栏、弹幕层都对），但画面偏色且很暗。原因在 libmpv：它的鸿蒙输出用 sRGB 的 Vulkan 交换链（10 位）渲染，再用 `OH_NativeWindow_SetColorSpace`、`SetMetadataValue` 给窗口打上 BT.2020 PQ 和 HDR10 元数据。渲染服务里看到的缓冲区：格式 RGBA_1010102、元数据类型 HDR10、静态元数据齐全、HDR 白点亮度 1.0，但色域字段仍是 sRGB，系统没有按 HDR 合成。`target-colorspace-hint=yes` 不改变交换链的选择（分叉里自带的 `set_color` 回调取代了 libplacebo 的色彩空间协商）；换 OpenGL 上下文则初始化失败。
- 所以不能靠 libmpv 自己渲染 HDR。

解决办法：让硬件解码器直接送显到这个图层，不经过 libmpv 的渲染。这是鸿蒙上播放 HDR 视频的常规做法，元数据由系统处理。

- cnoim 的 mpv 分叉里有现成的 `vo_ohcodec_embed`（提交 ec8b628「支持视频直通模式」，随后被 b1b1bc3 撤回，原先用的二进制对应撤回之后）。
- 已从源码重新编译 libmpv：mpv 取 ec8b628，其余依赖、FFmpeg 配置、补丁与原二进制的配方（参考仓库 `tool/native_mpv/`）相同。核对过 FFmpeg 配置行与 mpv 的 meson 配置行一致，导出符号 16747 个完全相同，只多出 `ohcodec_embed`。构建目录、脚本和日志在本机构建目录的 `libmpv-build/`，原二进制留有备份。
- 播放器补丁：HDR 画面层接上时把 `vo` 设为 `ohcodec_embed`，离开时换回 `gpu-next`。
- 开关怎么传给播放器：`OhosVideoController` 只存在于鸿蒙构建的补丁里，共用代码不能引用它，所以应用把 mpv 的 `script-opts` 设成 `ohos-hdr=yes`，控制器读它。试过 `user-data/…` 属性，从字符串接口写不进去。
- 代价：直通时 libmpv 的着色器、截图、色调映射都不可用，所以只在 PQ/HLG 的视频上启用。
- 画中画：小窗里只有 Flutter 的画面，HDR 的独立图层不会跟过去（实测小窗是黑的）。所以画中画期间让 HDR 视频退回纹理输出（映射为 SDR），退出后恢复。应用通过动态调用控制器的 `setHdrSuspended` 来切换。

HDR Vivid 的流（2026-11-14 实测，视频「华为HDRVIVID测试」，已登录）：

- 网页端接口（应用现在用的，`fnval=4048`、`qn=129`）：最高 125（HDR 真彩，`hvc1.2.4`，HDR10），没有 129。在 `fnval` 上再加任何一位（8192 到 262144 逐个试过）都返回 -400。
- 客户端 gRPC 接口 `/bilibili.app.playurl.v1.PlayURL/PlayView`（用仓库里现成的协议定义和 `GrpcReq`，身份是应用一直在用的安卓客户端）：`qn=129`，分别指定 HEVC 和 AV1，返回的画质列表同样最高 125，没有 129。
- 结论：HDR Vivid 不是「换成客户端接口」就能拿到的（用户决定不再自行探测，等别人做出来再参考）。两种接口在现有身份下给的画质相同。推断它只下发给特定的客户端身份或机型（例如官方鸿蒙客户端），这一点没有验证，也没有找到公开的实现或文档。
- 仓库里与客户端身份有关的现成东西：应用登录拿到的 `access_key`、`AppSign`、安卓客户端 8.43.0 的 UA 与设备信息、gRPC 请求封装、`/x/tv/playurl`（只用于投屏）。`lib/grpc/bilibili/app/playurl/v1` 的协议定义上游没有用来取流。

### 3.13 应用图标

- 分层图标（`AppScope/resources/base/media/app_layered_image.json`）：前景是 `assets/images/logo/logo_2.png` 放大到 1024，背景是纯色图。系统负责裁成各机型的外形。
- 背景随深浅色切换：`base/media/app_background.png` 是白色，`dark/media/app_background.png` 是 `#202522`。启动页背景色同样有 `dark` 版本。
- 桌面是否真的按深浅色取用 `dark` 目录下的背景，没有在真机上看到（当时屏幕熄灭）。

### 3.14 原生顶栏和底栏：暂不做

- 2.1 的做法能得到系统材质的外观，但要在 ArkTS 与 Flutter 之间同步显隐、裁剪、触摸，是那个仓库缺陷最集中的地方，而且要改动主页的骨架。
- 目前用 Flutter 画的导航，功能完整。先把功能和系统集成做完，再评估是否值得做原生栏。

## 4. 构建

鸿蒙包目前只在本机构建，构建脚本和下面这些补丁不在仓库里（仓库所有者的决定）：

- Flutter OH 3.47.7 的 SDK 补丁（上游 26 个补丁的移植）。
- `material_ui`、`cupertino_ui`、`cnativeapi` 的补丁。
- 上游两个 media-kit 分支的鸿蒙补丁。
- CPF `audio_service` 的修正（见 5.2）。
- `libmpv.so` 所在的 `media_kit_libs_ohos` 包。

仓库内与构建有关的文件：`ohos/`（宿主工程）、`ohos/pubspec_ohos.yaml`、`ohos/patches/lib-target-platform.patch`。

构建步骤的顺序：放宽 `pubspec.yaml` 的 Flutter 版本 → 并入鸿蒙依赖 → 应用 `lib` 补丁 → 上游的 `build.ps1` → SDK 补丁 → `pub get` → 包补丁 → `flutter build hap`。

## 5. 遇到的第三方缺陷

1. `cnativeapi` 的构建钩子把鸿蒙目标当成 Linux 去找 GTK：补丁里跳过。
2. CPF `audio_service`：Dart 传 `queueIndex: null` 时把 `activeItemId` 设成 null，系统以 401 拒绝，整次播放状态上报丢失：补丁里只在是数字时才设。
3. CPF `dynamic_color`：见 3.6。
4. CPF `share_plus` 的接口包把 `path_provider` 指向 git 上的旧分支：在依赖里改回 pub 的版本。
5. gitcode 拒绝匿名的 LFS 下载：构建时跳过 LFS（涉及的都是示例资源）。
6. `file_picker_ohos` 声明的接口版本是 3.x，应用用的是 4.x：两版只差一处返回类型，强制用 4.x。
7. 图片裁剪的鸿蒙实现只到 12.2.1：整包换成它，接口包仍用 9.x，只用到它的原生部分。

## 6. 调试方法

- 正式包里 Dart 的未捕获异常不进系统日志，`print` 会进。定位启动问题时，在构建目录里临时给 `main()` 套一层把错误画到屏幕上的代码。
- 渲染服务的状态：`hidumper -s RenderService -a RSTree` 看图层，`-a 'surfacenode <id>'` 看某个 surface 的缓冲区格式、色域、HDR 元数据。
- libmpv 的详细日志：把 `PlayerConfiguration.logLevel` 调到 `.v` 并监听 `player.stream.log`。
- 解码测试：临时每 2 秒打印 mpv 的 `hwdec-current`、丢帧数等属性。强制首选编码会写进手机上应用的设置，测完要清掉。
- 自动点击：`uitest uiInput click` 每次约 1 秒；播放器的控制栏会自动隐藏，要先点一下视频、截一次图，再点按钮。

## 7. 已在真机验证

设备：Mate XTs（HarmonyOS 7.0，API 26）。

- 启动、首页（折叠态与全展开）、主题色。
- 视频页、播放、弹幕、控制栏、全屏进入与退出。
- 转屏（用户验证），含折叠态启动后展开。
- 控制中心的媒体卡片：显示、播放状态、暂停播放、快进快退（用户与自动点击都验证过）。
- H.264、HEVC 硬解与 AV1 软解（1080p30）。
- 主界面返回键。
- 画中画：手动进入、回到应用后恢复布局。
- 应用链接：`bilibili://video/…` 打开视频页，`bilibili://browser?url=…` 打开应用内网页（网页能加载），`bilibili://live/…` 打开直播间（当时未开播），`bilibili://login` 打开登录页，`bilibili://search?keyword=…` 打开搜索结果。

其他平台：

- `feature/harmony` 用官方 Flutter 3.47.9 能出 iOS 包，25 项测试通过（2026-11-14）。安卓没有在本机构建过。

## 8. 待验证

需要登录或需要人手操作，尚未验证：

- 登录本身（密码、短信、扫码、极验验证码的网页视图）。
- 评论与私信的输入框（键盘高度、表情面板）。
- 文件选择（导入导出、字体）、图片裁剪（头像、收藏夹封面）。图片裁剪的风险最高。
- 保存图片与视频到图库；保存动态照片（已实现，未测）。
- 分享、打开外部链接、应用内网页。
- 亮度手势、离开播放页后亮度复位、系统关闭自动旋转时不自动全屏。
- 画中画：小窗上的按钮、后台自动进入、直播间、小窗里的弹幕、展开态。
- 4K、60 帧、HDR、杜比视界的解码（用户要求放到最后一起测）。
- 声音是否正常、音量均衡是否生效。
- nova 14（API 24）上的表现。

## 9. 已知不完整

- 个人主页的「添加至桌面」在鸿蒙上不显示（没有对应的系统接口）。
- 日志里偶尔出现的 `MethodChannel# --> method not implemented` 来自 `SystemNavigator.setFrameworkHandlesBack`：这是安卓预测性返回用的调用，Flutter OH 的嵌入层没有实现，可以忽略。
- 暂停状态下从控制中心快进快退，卡片上的进度要到恢复播放后才更新（应用自身的去重逻辑，各平台都有）。
- 倾斜角度阈值在鸿蒙上不生效（设置项不显示）。
- 网页视图、登录验证码、投屏几处的平台分支没有细看。
- 还没做：桌面卡片、接续。
