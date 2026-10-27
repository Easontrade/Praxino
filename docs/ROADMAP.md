# Praxino 路线图与任务卡

每张任务卡都能独立完成、独立提交。**按编号顺序做**，前面的任务是后面任务的基础。
开始前先读 [`ARCHITECTURE.md`](ARCHITECTURE.md) 和仓库根目录的 [`AGENTS.md`](../AGENTS.md)。

每张卡的格式：**目标 / 涉及文件 / 做法 / 验收标准**。验收标准全部满足才算完成。
每张卡完成后都必须：`flutter analyze` 无问题、`flutter test` 全部通过、一个 Conventional Commit。

状态：✅ 完成　🟡 部分完成（卡片内注明缺口）　⏳ 待做　⛔ 不在当前范围

在线源不依赖任何外部项目：Kazumi 规则只作为**可选的输入格式**和手动测试数据；
可靠性、弹幕匹配等策略都由本项目自己实现，不复制、不移植外部代码。

卡片里需要"手动"验证的地方（画面、声音、快捷键、安装包）由用户在方便时执行；
代理只跑无窗口的命令（`flutter analyze` / `flutter test` / `flutter build`），不要自己弹出播放器。

---

## M0 骨架 ✅

- ✅ Flutter + media_kit 工程，Windows 可构建（debug / release）
- ✅ 本地播放：打开文件 / 拖入 / 命令行参数 / 同目录自动成播放列表（自然排序）/ 最近播放
- ✅ 外挂字幕：按钮或拖入加载，libass 渲染，同名字幕自动加载
- ✅ L1 画质增强：Anime4K 三档 + 去色带 + 降噪，持久化，跨集保持
- ✅ `SourceAdapter` 接口 + Kazumi 规则适配器（xpath / api 搜索与选集），带单测

---

## M1 本地播放打磨（最高优先级）

### M1-1 快捷键与焦点 ✅
- **目标**：播放页里 `Ctrl+0~3`、`Ctrl+E` 一定能生效，并补齐常用键。
- **文件**：`lib/ui/player_page.dart`、`lib/core/player/praxino_player.dart`
- **做法**：
  1. 先确认现有的 `CallbackShortcuts` + `Focus(autofocus: true)` 是否生效（按 AGENTS.md 的
     "手动验证"一节：代理不要自己在桌面上弹出播放器）。注意 media_kit 的
     `MaterialDesktopVideoControls` 内部还有一个 `Focus(autofocus: true)`
     （`videoViewParameters(context).value.focusNode`）和一套默认快捷键，两层 Focus 会争抢焦点。
  2. 如果不生效，把完整的快捷键表通过 `MaterialDesktopVideoControlsThemeData.keyboardShortcuts` 传入。
     这个字段会**替换** media_kit 的默认表，所以要把默认键全部补回去，而不是只补空格/方向键/F/Esc：
     当前 `material_desktop.dart` 的表包含 `Space`、`J`/`I`（±10s）、`←`/`→`（±2s）、
     `↑`/`↓`（音量）、`F`、`Esc`，以及媒体键 5 个（播放/暂停/播放暂停/下一曲/上一曲）。
  3. 新增：`Z`/`X` 字幕延迟 −/+0.1s（mpv 属性 `sub-delay`）、`[`/`]` 播放速度 ±0.1（`speed`）、
     `S` 截图（mpv 命令 `screenshot`，存到"图片/Praxino"）。
     这些都要先在 `PraxinoPlayer` 里加方法，UI 只调方法。
  4. 把快捷键集中到一张表里（动作 → 按键），不要散落在 `build` 里；M1-7 会接设置页并持久化。
- **验收**：每个新快捷键按下都有 SnackBar 反馈，并且实际生效；播放页里按空格会暂停，不会触发别的按钮；
  media_kit 的默认键在改过快捷键表之后仍然可用。

### M1-2 续播 ✅
- **目标**：重新打开同一个文件时，从上次的位置继续播放。
- **文件**：`lib/core/library/watch_history.dart`（新建）、`lib/core/settings/settings_store.dart`、
  `lib/ui/player_page.dart`、`test/watch_history_test.dart`（新建）
- **做法**：以"文件绝对路径"为 key，保存 `position`、`duration`、更新时间；每 5 秒和退出时各写一次；
  打开时如果 `position > 10s` 并且离结尾 > 30s，就 seek 过去，显示"已从 12:34 继续，点此从头播放"。
  最多保留 500 条，按时间淘汰。
- **验收**：单测覆盖淘汰逻辑和"接近结尾不续播"的判断；手动关掉再开，确实从上次位置继续。

### M1-3 播放列表侧栏 ✅
- **目标**：播放页右侧可展开的选集面板，显示同目录的所有集，当前集高亮，点击切换。
- **文件**：`lib/ui/playlist_panel.dart`（新建）、`lib/ui/player_page.dart`
- **做法**：数据来自 `player.stream.playlist`；按钮放在底栏，快捷键 `L`；
  切集后保持当前画质设置（由 `PraxinoPlayer.setEnhance` 负责）。
- **验收**：10 集以上的文件夹能正常滚动，当前集高亮正确，切集后超分设置不变。

### M1-4 轨道菜单 ✅
- **目标**：底栏增加音轨/字幕轨选择菜单（含"关闭字幕"和"第二字幕"）。
- **文件**：`lib/ui/track_menu.dart`（新建）、`lib/ui/player_page.dart`、`lib/core/player/praxino_player.dart`
- **做法**：数据来自 `player.state.tracks`；在 `PraxinoPlayer` 加 `setAudioTrack` / `setSubtitleTrack` /
  `setSecondarySubtitleTrack`；第二字幕用 mpv 属性 `secondary-sid`；关闭字幕用 `SubtitleTrack.no()`。
- **验收**：双语 MKV 能同时显示中英两条字幕；关闭字幕再打开能恢复。

### M1-5 文件关联和单实例 ✅
- **目标**：Windows 下双击视频用 Praxino 打开；已打开时把文件交给现有窗口，而不是再开一个窗口。
- **文件**：`windows/runner/main.cpp`、`windows/runner/flutter_window.{h,cpp}`、
  `windows/runner/utils.cpp`、`lib/core/platform/single_instance.dart`（新建）、`lib/main.dart`
- **做法**：
  1. 首次启动的 argv 已经由 `windows/runner/main.cpp` 的 `GetCommandLineArguments()` 转发给 Dart，
     这里只需要处理"第二个实例把 argv 交给第一个实例"。
  2. Windows 侧用命名互斥量判断是否已有实例；有就把命令行通过 `WM_COPYDATA` 发给已有窗口。
  3. Dart 侧用 MethodChannel 接收消息，交给 `HomePage` 打开文件。
  4. 文件关联在安装包里做（M6-1），这里只做单实例。
- **验收**：连续两次 `praxino.exe a.mkv`、`praxino.exe b.mkv`，只有一个窗口，并且在播 b；
  路径含中文/空格也能正确传递。

### M1-6 排查 MP4 的 NAL 报错 ✅
- **目标**：查清播放带 `bin_data` 数据轨的 MP4 时日志刷屏 `Invalid NAL unit size` /
  `missing picture in access unit` 的原因（独立版 mpv 播同一文件没有这些报错，画面目前正常）。
- **文件**：`lib/core/player/praxino_player.dart`（若需要调整 demuxer 选项）、
  `docs/ARCHITECTURE.md`（把结论写进"已知无害日志"或修复说明）
- **做法**：先试 mpv 选项 `--vid`/`--aid`/`--sid`、`--demuxer-lavf-o=…` 排除数据轨，再试 `hwdec=no` 对照，
  确定是 media_kit 自带 ffmpeg 的问题还是参数问题。
- **结论**：无窗口无法复现。独立 mpv 0.41、media_kit 自带 libmpv 0.36（FFmpeg n6.0，
  `vo=null`/`ao=null`）和 ffmpeg 解码 300 帧均无报错；不修改 demuxer，保留为历史观察。
- **验收**：有结论；如果能修就修，修不了要在文档里写明原因和影响范围。

### M1-7 设置页与快捷键自定义 ✅
- **目标**：设置页可以查看/修改播放器快捷键，修改立即生效并持久化；
  后续路径、凭据、画质默认值也放在这里。
- **文件**：`lib/ui/settings_page.dart`（新建）、
  `lib/core/settings/keybindings.dart`（新建：动作/默认键/序列化）、
  `lib/core/settings/settings_store.dart`、`lib/ui/home_page.dart`（入口）、
  `lib/ui/player_page.dart`、`test/keybindings_test.dart`（新建）
- **做法**：
  1. 定义 `PlayerAction` 枚举和默认绑定表；键用可序列化的描述（如 `ctrl+1`、`space`），
     UI 层再转成 `SingleActivator`，`core` 不依赖 Flutter 控件。
  2. 设置页列出动作、当前键和"重置"；录制新键时检测冲突（同一组合只能绑一个动作），
     冲突时提示并拒绝保存。
  3. 保存到 `SettingsStore`（JSON）；播放页启动时读取，未知动作或无法解析的键忽略并回退默认。
  4. 先只做播放器动作；画质默认值、yt-dlp 路径、弹幕/字幕凭据后续加到同一页面。
- **验收**：改键后播放页立即生效，重启后仍在；冲突有提示且不能保存；重置恢复默认；
  单测覆盖序列化、冲突和回退。

---

## M2 画质增强进阶

### M2-1 真人片超分预设 ✅
- **目标**：增加适合实拍片的超分（Anime4K 会把实拍画面涂抹）。
- **文件**：`lib/core/enhance/enhance_settings.dart`、`assets/shaders/fsrcnnx/`（新建，含 LICENSE）、
  `lib/core/player/praxino_player.dart`、`lib/ui/enhance_menu.dart`、`test/core_test.dart`
- **做法**：
  1. 引入 FSRCNNX x2 16-0-4-1（或 ArtCNN），放到 `assets/shaders/fsrcnnx/`，附上各自的 LICENSE。
  2. `UpscalePreset` 增加枚举值和 `shaderFamily`（`anime4k` / `fsrcnnx`），
     `PraxinoPlayer` 按预设选择 `<exe>/data/flutter_assets/assets/shaders/<family>`，
     不要继续写死 `anime4k`。
  3. 菜单按"动画 / 实拍"分组显示；设置仍然持久化。
- **验收**：单测覆盖新预设的属性生成和路径顺序；1080p 实拍片手动对比，开关前后差异可见、没有涂抹感；
  `flutter analyze` / `flutter test` 通过。

### M2-2 自动选择预设 🟡

> 🟡 部分完成：降档策略有单测；未在真实掉帧的核显上验证。
- **目标**：根据片源分辨率和显卡性能推荐档位，用户可以覆盖。
- **文件**：`lib/core/enhance/enhance_advisor.dart`（新建，纯函数）、
  `lib/core/player/praxino_player.dart`（暴露帧率和掉帧统计）、
  `lib/ui/player_page.dart`、`test/enhance_advisor_test.dart`（新建）
- **做法**：读取 mpv 属性 `video-params/h`、`estimated-vf-fps`、`frame-drop-count`、
  `vo-delayed-frame-count`；连续 3 秒掉帧比例超过 5% 就自动降一档并提示；
  用户手动选过之后 30 分钟内不再自动改；降到"关闭"为止。
- **验收**：单测覆盖降档规则和用户覆盖；在核显上播 1080p 选"高质量"，10 秒内自动降档并提示。

### M2-3 增强包与补帧（RIFE / mvtools） 🟡

> 🟡 部分完成：**应用内 mvtools 和 RIFE 补帧都已打通**（隐藏桌面实测，1080p）：
> mvtools 23.976 → 59.94 fps；RIFE 23.976 → 47.952 fps（2 倍），启动后不再掉帧。
> 剩余：掉帧提示降档（第 5 步）、真人肉眼观感、增强包一键安装 RIFE 插件和模型。
>
> 之前的"API 2.1/2.6 不兼容"是误判：真正原因是进程里加载了**两份** libmpv（见 ARCHITECTURE §5.2）。
> 实测：2023-07 的 shinchiro 构建（mpv 0.35.0-579，API 2.1）用旧方式同样崩溃，放进应用目录后又因为太旧、
> 找不到 VapourSynth R81 的入口而退出（0xC06D007F）；当前的 2026 构建（API 2.6）放进应用目录后正常工作。
> 结论：用当前 shinchiro 构建即可，**不需要旧构建，也不需要 fork media_kit**。
- **目标**：通过可选的"增强包"让 mpv 支持 VapourSynth，实现实时补帧。设计见 ARCHITECTURE §5.2。
- **文件**：`lib/core/enhance/enhance_pack.dart`（新建：下载/校验/安装）、
  `lib/core/enhance/interpolation.dart`（新建：vf 组合与 vpy 参数）、
  `assets/vapoursynth/*.vpy`（新建）、`lib/main.dart`（启动时选择 libmpv）、
  `lib/ui/enhance_menu.dart`、`test/enhance_pack_test.dart`（新建）
- **做法**：拆成五步，各自提交：
  1. 先验证：用当前 libmpv 试 `vf=vapoursynth`（或看 `mpv --list-filters` 里有没有 vapoursynth），
     确认是否真的不支持；如果支持，直接跳到第 3 步。
     ✅ 结论：media_kit 自带的 libmpv 不含 VapourSynth，需要增强包。
  2. ✅ 增强包下载器和版本校验（SHA256）：清单包含 URL、版本、哈希；下载到
     `%APPDATA%/Praxino/enhance-pack/`；校验失败删除并报错。
  3. ✅ 启用 = 替换应用目录里的 `libmpv-2.dll`（`EnhancePackActivation`，重启生效）；
     **不要**用 `MediaKit.ensureInitialized(libmpv:)` 另外加载一份。VapourSynth 运行时路径在设置页填写，
     启动时由 `VapourSynthRuntime` 写入进程环境（Win32 + C 运行时两份）。
  4. ✅ `EnhanceSettings.interpolation`（`off / mvtools / rife`）+ `.vpy` 模板，每种模式默认用内置模板，
     设置里的自定义 `.vpy` 只作覆盖：
     - `assets/vapoursynth/mvtools_flowfps.vpy`：读 mpv 注入的 `video_in`/`container_fps`，输出约 60fps。
     - `assets/vapoursynth/rife_ncnn.vpy`：VapourSynth-RIFE-ncnn-Vulkan 插件 + RIFE v4.6 模型，输出 2 倍帧率。
       选型过程：vs-mlrt 的 Windows 插件（NCNN/ORT/TRT）都还是 VapourSynth API 3，R81 已不支持；
       vs-rife 需要数 GB 的 CUDA 版 PyTorch。RIFE-ncnn-Vulkan 是 API 4、单个 5MB DLL、任意显卡可用。
       帧率选择：固定 60fps 需要每 5 帧推理 4 帧，RTX 5080 上 1080p 只有约 40fps（GPU 100%）；
       2 倍只需每 2 帧推理 1 帧，约 60fps 吞吐，实时有余量。
     - 补帧滤镜与 L1 的 `hqdn3d` 已合并进同一条 `vf` 链。
     - 应用目录**不能**带 media_kit ANGLE 包里的开发版 `vulkan-1.dll` / `vk_swiftshader.dll`
       （已在 `windows/CMakeLists.txt` 排除），否则 RIFE 一初始化就在 NVIDIA 驱动里崩溃，原因见 ARCHITECTURE §5.2。
  5. 显示 `frame-drop-count`，掉帧时提示降档。
- **验收**：24fps 片源开启后，`estimated-vf-fps` 约等于显示器刷新率；关闭后能恢复；
  降噪和补帧可以同时开启且两者都生效；增强包缺失/校验失败时不影响普通播放。

### M2-4 画质对比模式 🟡

> 🟡 部分完成：对比状态与播放器接线有单测；未做实际画面目测。
- **目标**：按住某个键时显示原始画面（松开恢复），用来对比增强效果。
- **文件**：`lib/core/player/praxino_player.dart`、`lib/ui/player_page.dart`
- **做法**：按住时暂存当前 `glsl-shaders` 再清空，松开时写回；对比期间不要改动持久化的 `EnhanceSettings`；
  如果对比期间用户改了预设，保存值要同步更新，避免松开后恢复成旧设置。
- **验收**：按住显示原画、松开恢复；暂停时也能用；对比前后 `flutter analyze` / `flutter test` 通过。

---

## M3 在线源

### M3-1 SourceRegistry 与订阅 ✅
- **目标**：用户添加订阅 URL → 下载 JSON → 解析成若干 `SourceAdapter` → 本地缓存 → 可启用/禁用。
- **文件**：`lib/core/sources/source_registry.dart`（已实现并发搜索，订阅待接）、
  `lib/core/sources/subscription.dart`（新建）、
  `lib/core/storage/app_database.dart`（新建，drift）、`lib/core/settings/settings_store.dart`、
  `pubspec.yaml`、`test/source_registry_test.dart`（已建）
- **做法**：可选地兼容 KazumiRules 的规则列表格式（`plugins.json` 那种规则数组）和单个规则 JSON；
  这只是输入格式，不引入对 Kazumi 代码的依赖；格式探测按字段判断；
  下载后按 `name` + `version` 去重；缓存带 `fetchedAt` 和 `etag`；
  启用状态和规则存入 SQLite（drift），旧的 `shared_preferences` 数据做迁移或明确重置。
- **验收**：单测用 `MockClient` 覆盖：下载成功、解析失败的条目跳过但不影响其它条目、版本比较、
  启用/禁用持久化；测试不访问网络。

### M3-2 搜索页与详情页 ✅
- **目标**：首页增加"在线"标签：搜索框 → 对所有启用的源并发搜索（每个源单独超时 10s）→
  结果按源分组 → 点进去选线路和集数。
- **文件**：`lib/core/sources/search_service.dart`（新建）、`lib/ui/search_page.dart`（新建）、
  `lib/ui/media_detail_page.dart`（新建）、`lib/ui/home_page.dart`、`test/search_service_test.dart`（新建）
- **做法**：用 `SourceRegistry.search` 的流式结果，每个源单独超时；单个源出错只在它的分组里显示错误，
  不影响其它源；结果里的 `PlayableStream` 可带 height/bitrateKbps/subtitleLanguages，
  UI 据此排序或筛选；结果为空、全部失败、加载中都要有明确状态。
- **验收**：一个源超时不影响其它源出结果；单测用假适配器覆盖超时、异常、空结果。

### M3-3 StreamSniffer（WebView2） 🟡

> 🟡 部分完成：WebView2 后端与详情页接入完成；未用 3 个私有源实播验证。
- **目标**：`resolve()` 返回 null 的源，用隐藏的 WebView2 加载播放页，
  捕获第一个 `.m3u8`/`.mp4` 请求（含 iframe 里的）。
- **文件**：`lib/core/sources/sniffer/webview_sniffer.dart`（新建）、`lib/ui/player_page.dart`、
  `pubspec.yaml`、`test/webview_sniffer_test.dart`（新建，只测 URL 匹配等纯逻辑）
- **做法**：优先用 `webview_windows`；先确认它是否暴露资源请求拦截，没有就换
  `flutter_inappwebview` 的 Windows 实现。监听请求事件；15 秒超时；
  把捕获到的 Referer、UA、Cookie 一起放进 `PlayableStream.headers`；命中第一个就停。
- **验收**：用私有测试规则（见 `AGENTS.local.md`）手动测试（只作测试数据，
  **不要把规则提交进仓库**），至少 3 个源能播放；超时返回 null 并由 UI 提示；纯逻辑（URL 判定/请求头合并）有单测。

### M3-4 可靠性策略（自己实现） 🟡

> 🟡 部分完成：标题匹配/探测/切换/预取有单测；未做断网 5 秒的真实故障切换。
- **目标**：搜索排序、源探测、自动选源、故障切换、下一集预取。
- **文件**：`lib/core/sources/reliability/title_match.dart`、
  `lib/core/sources/reliability/source_prober.dart`、
  `lib/core/sources/reliability/auto_switch.dart`、
  `lib/core/sources/reliability/prefetch.dart`（均为新建）、`lib/ui/player_page.dart`、
  `test/title_match_test.dart`、`test/auto_switch_test.dart`（均为新建）
- **做法**：自己设计并在 `reliability/` 下实现：
  1. 标题匹配：归一化（大小写/标点/全半角/中文数字），提取季数和集数；
     用"标题相似度 + 季数 + 集数"打分，低于阈值的不参与自动选源。
  2. 源探测：对候选并发做轻量请求（HEAD 或 `Range: bytes=0-0`），
     记录是否可达和首包延迟；每个探测都有超时和取消，单个源失败不影响其它源。
  3. 自动选源：先用标题分筛出候选，再在标题分相近的候选里按探测延迟排序，选第一个可用源；
     没有可用源时把错误交回 UI。
  4. 故障切换：播放 watchdog 监听 error/buffering；超过阈值切到下一个候选并 seek 回原位置；
     记录失败源，短期不再重试，避免来回跳。
  5. 预取：当前集播放 30 秒后解析下一集，临近结尾再刷新一次；切集时取消旧任务。
- **验收**：单测覆盖打分和切换逻辑；手动测试时断网 5 秒能自动换源继续播；
  预取失败不影响当前集播放。

### M3-5 yt-dlp 适配器 🟡

> 🟡 部分完成：Mock 覆盖格式选择；未用真实公开视频手动验证。
- **目标**：粘贴任意视频页链接就能播放。
- **文件**：`lib/core/sources/ytdlp/ytdlp_adapter.dart`（新建）、
  `lib/core/process/process_runner.dart`（新建，可注入，便于测试）、
  `lib/core/settings/settings_store.dart`（yt-dlp 路径）、`test/ytdlp_adapter_test.dart`（新建）
- **做法**：查找 `yt-dlp.exe`（同目录/PATH 优先；自定义路径在 M1-7 设置页补；找不到时提示下载），
  运行 `yt-dlp -J --no-playlist <url>`（用 `Process.run` 参数列表，不拼 shell），
  选最佳的"视频+音频"格式；音视频分离时用 mpv 的 `audio-files` 属性挂上音频；
  超时、退出码、JSON 解析错误都要有明确错误信息。
- **验收**：单测模拟 yt-dlp 输出的 JSON（单流/分离流/多格式）；手动测一个公开视频能播；
  找不到 exe 时有提示而不是崩溃。

### M3-6 TVBox（苹果 CMS 接口）适配器 ✅
- **目标**：兼容 TVBox 配置里 `type: 0`（XML）和 `type: 1`（JSON）的 `api` 站点。
- **文件**：`lib/core/sources/tvbox/tvbox_adapter.dart`（新建）、
  `test/tvbox_adapter_test.dart`、`test/fixtures/tvbox/*.xml`、`*.json`（新建，示例域名用 `example.test`）
- **做法**：只支持 `type 0/1`；`type: 3` 的 JAR/Python 爬虫**不支持**（不执行远程代码）；
  实现 `ac=list`、`ac=detail`，解析 `vod_play_url` 的 `$` / `#` / `$$$` 分隔规则。
- **验收**：fixture 覆盖分隔规则、空字段、多条线路；遇到 `type: 3` 明确拒绝并说明原因。

### M3-7 WebDAV / OpenList 源 🟡

> 🟡 部分完成：PROPFIND 客户端、目录浏览、Basic 认证、同目录视频播放列表、服务器管理已完成并有 fixture；未用真实 OpenList 验证，同目录字幕自动挂载和服务器级续播 key 未接。

- **目标**：浏览并串流播放用户自己网盘里的视频（夸克、百度、阿里云盘等经 OpenList/Alist 挂成 WebDAV，
  或任意 WebDAV 服务）。优先级高于继续增加站点类源。
- **文件**：`lib/core/sources/webdav/webdav_client.dart`、`webdav_adapter.dart`（新建）、
  `lib/ui/webdav_browser_page.dart`（新建）、`lib/core/settings/settings_store.dart`、
  `test/webdav_client_test.dart`（新建，PROPFIND 响应用 fixture）
- **做法**：
  1. 自己实现最小 WebDAV 客户端：`PROPFIND Depth: 1` 列目录（解析 multistatus XML），
     Basic 认证；不引入大型依赖。
  2. 目录页按自然排序显示文件夹和视频；点视频时把**同目录视频**组成播放列表（复用 `naturalCompare`）。
  3. 播放时把认证放进 mpv 请求头（`PlayableStream.headers`），**不要**把用户名密码拼进 URL，日志里也不能出现。
  4. 同目录的 `.ass/.srt` 自动作为外挂字幕；续播以"服务器地址 + 路径"为 key 复用 `WatchHistory`。
  5. 凭据存本机设置（同 OpenSubtitles 的存法），设置页可增删多个服务器。
- **验收**：fixture 覆盖目录解析、中文/空格路径编码、401；用户本机连 OpenList 能列目录并播放、
  下一集和续播生效；日志和崩溃信息里搜不到密码。

### M3-8 Jellyfin / Emby 客户端 ⏳
- **目标**：连接用户自建的 Jellyfin/Emby 媒体服务器，显示媒体库和海报墙，播放并同步观看进度。
- **文件**：`lib/core/sources/jellyfin/jellyfin_client.dart`、`jellyfin_adapter.dart`（新建）、
  `lib/ui/library_page.dart`（新建）、`test/jellyfin_client_test.dart`（新建）
- **做法**：
  1. 用户名密码登录（`/Users/AuthenticateByName`）拿 token，只保存 token；Emby 与 Jellyfin 共用一套实现，
     差异处用开关处理。
  2. 媒体库 → 剧集/季/集 → 播放；优先 **Direct Play**（原文件直出，才能发挥超分），不行再用服务器转码。
  3. 播放进度定时上报（`/Sessions/Playing/Progress`），打开时从服务器进度续播。
  4. 服务器上的外挂字幕按语言自动挂载，中文优先。
- **验收**：`MockClient` 覆盖登录、分页、进度上报、token 失效；用户本机连自己的服务器能播放并同步进度。

---

## M4 弹幕与更多源

### M4-1 弹幕渲染层 ✅
- **目标**：在 `Video` 之上叠一层弹幕：滚动、顶部、底部三种；可调透明度、字号、显示区域、密度。
- **文件**：`lib/core/danmaku/danmaku_engine.dart`（新建，纯调度：轨道分配/时间窗口/密度上限）、
  `lib/ui/danmaku/danmaku_overlay.dart`（新建，CustomPainter + Ticker）、
  `lib/ui/player_page.dart`、`test/danmaku_engine_test.dart`（新建）
- **做法**：先评估 `canvas_danmaku` 包；不合适就自写 `CustomPainter` + `Ticker`。
  播放时间跟随 `player.stream.position`，seek 时重新排布，暂停时冻结，退出时释放。
- **验收**：1000 条/分钟的弹幕下仍能稳定 60fps（用 Flutter DevTools 查看）；
  seek 后没有残影；单测覆盖轨道分配和密度上限。

### M4-2 弹弹play 提供者 🟡

> 🟡 部分完成：客户端/匹配/凭证/UI 完成；缺少审核通过后的真实 AppId 在线验证。
- **目标**：本地文件和在线剧集都能匹配到弹幕。
- **文件**：`lib/core/danmaku/dandanplay_provider.dart`（新建）、
  `lib/core/danmaku/danmaku_matcher.dart`（新建）、`lib/core/settings/settings_store.dart`（凭证）、
  `lib/ui/player_page.dart`、`test/dandanplay_provider_test.dart`（新建）
- **做法**：自己做匹配与记忆：
  1. 本地文件用"前 16MB MD5 + 文件名 + 大小"生成 key；在线剧集用"标题 + 季 + 集"生成 key。
  2. 先查本地记忆（key → 提供者/集 id），没有再调提供者搜索；搜索失败回退到标题搜索。
  3. 用户手动选择后写入记忆（带时间戳），下次优先使用；提供者返回失效时清除记忆并重新搜索。
  4. AppId/Secret 从环境变量 `PRAXINO_DANDAN_APP_ID` / `PRAXINO_DANDAN_APP_SECRET`
     读取（设置页在 M1-7 再补可视化配置），**不提交到仓库**。
- **验收**：本地番剧文件能自动匹配；手动选过的匹配下次直接使用；凭证缺失时有提示；
  单测用 `MockClient` 覆盖命中/失败/记忆。

### M4-3 Stremio addon 适配器 🟡

> 🟡 部分完成：adapter 与管理 UI 完成；未接真实 addon 验证。
- **目标**：通过 Stremio addon 的 HTTP 协议获取剧集和流。
- **文件**：`lib/core/sources/stremio/stremio_adapter.dart`（新建）、
  `test/stremio_adapter_test.dart`（新建）
- **做法**：实现 `/manifest.json`、`/catalog`、`/meta`、`/stream`；
  只接受 http(s) 的 addon 地址；解析 stream 的 URL 和 headers；超时和错误按 M3-2 的约定聚合。
- **验收**：fixture 覆盖 manifest/catalog/stream；一个公开 addon 手动测试能播。

### M4-4 脚本源（QuickJS 沙箱） 🟡

> 🟡 部分完成：QuickJS 沙箱与脚本 adapter 已验证；没有真实脚本源做端到端。
- **目标**：支持用脚本写的小型源，但**不执行任意远程代码**。
- **文件**：`lib/core/sources/script/script_adapter.dart`（新建）、
  `lib/core/sources/script/quickjs_host.dart`（新建，FFI）、
  `test/script_adapter_test.dart`（新建）
- **做法**：QuickJS 沙箱只暴露 `fetch`、`parseHtml`、`log`；`fetch` 走可注入的 `http.Client`
  并限制协议/超时；设置内存和时间上限；不暴露文件系统、进程、动态库；脚本来源要显示哈希。
- **验收**：单测覆盖超时、异常、内存/时间超限；脚本无法读文件或执行命令；
  `flutter analyze` / `flutter test` 通过。

---

## M5 字幕与离线处理

### M5-1 在线字幕搜索（ASSRT、OpenSubtitles） 🟡

> 🟡 部分完成：provider/落盘/设置完成；没有真实 ASSRT/OpenSubtitles 账号验证。
- **目标**：按标题/季/集搜索字幕，下载到视频同目录的 `subs/` 并自动加载。
- **文件**：`lib/core/subtitles/subtitle_provider.dart`（新建接口）、
  `lib/core/subtitles/assrt_provider.dart`、`lib/core/subtitles/opensubtitles_provider.dart`（新建）、
  `lib/ui/subtitle_search_dialog.dart`（新建）、`lib/ui/player_page.dart`、
  `test/subtitle_provider_test.dart`（新建）
- **做法**：搜索 → 按语言/格式/评分排序 → 下载 → 保存为 `<视频名>.<语言>.<ext>`；
  凭据从环境变量读取（`PRAXINO_ASSRT_TOKEN` / `PRAXINO_OPENSUBTITLES_API_KEY`；
  设置页在 M1-7 再补）；请求限流；失败时给出可读错误。
- **验收**：`MockClient` 覆盖搜索/下载/失败；手动搜索并加载一条字幕；
  下载的文件出现在 `subs/` 且能被 libass 加载。

### M5-2 离线超分 / 补帧任务队列 ✅
- **目标**：后台批量处理视频，输出增强后的新文件，可暂停/继续/取消。
- **文件**：`lib/core/enhance/offline/offline_job.dart`、
  `lib/core/enhance/offline/offline_queue.dart`、
  `lib/core/enhance/offline/ffmpeg_runner.dart`（均为新建）、
  `lib/ui/offline_tasks_page.dart`（新建）、`lib/core/settings/settings_store.dart`、
  `test/offline_queue_test.dart`（新建）
- **做法**：任务状态机（排队/运行/暂停/完成/失败），支持取消和断点续做；
  ffmpeg 解码 → Real-ESRGAN-ncnn-vulkan / RIFE-ncnn-vulkan → ffmpeg 编码；
  输出到同目录 `_enhanced.mp4`；检测工具路径和 GPU；解析 ffmpeg 进度；失败可重试。
- **验收**：单测覆盖队列状态机和断点；用 1 分钟片段做端到端处理；
  失败任务能重试且不破坏原文件。

### M5-3 AI 双语字幕（本地识别 + 大模型翻译） ⏳
- **目标**：为没有字幕或只有外语字幕的视频生成中英双语字幕。主要面向本地文件、网盘和 Jellyfin 片源；
  站点源大多是硬字幕，不需要。
- **两步走**：大模型不接收音频，所以先用**本地 Whisper** 做语音识别（免费），再用**大模型翻译**。
- **文件**：`lib/core/subtitles/ai/transcriber.dart`（Whisper 调用）、`translator.dart`（翻译接口）、
  `claude_translator.dart`、`bilingual_ass.dart`（生成双语 ASS）、`ai_subtitle_job.dart`（接入离线队列）（均新建）、
  `lib/ui/settings_page.dart`、`lib/ui/offline_tasks_page.dart`、
  `test/bilingual_ass_test.dart`、`test/claude_translator_test.dart`、`test/ai_subtitle_job_test.dart`（新建）
- **做法**：
  1. **任务类型**：在 M5-2 的离线队列里加 `AiSubtitleJob`，可排队、取消、失败重试；同一文件
     （以路径 + 大小 + 修改时间为 key）已生成过就直接复用，不重复计费。
  2. **提取音频**：ffmpeg 提取单声道 16kHz WAV 到临时目录，任务结束删除。
  3. **识别**：调用本地 `faster-whisper`（推荐 `large-v3-turbo`，GPU）或 `whisper.cpp` 的命令行，
     工具路径在设置页配置（同离线 GPU 工具）；输出带时间轴的 SRT；源语言可自动检测或手动指定。
  4. **术语表**：先把全文发给模型一次，提取人名、地名、专有名词及固定译法（JSON），后续每段都带上，
     保证整集译名一致。
  5. **分段翻译**：每段约 40～60 句，附前后各 5 句作为上下文；要求按句号返回结构化结果
     （用 structured outputs，按 `id` 对齐，不能合并或拆分句子），对齐失败的段落重试一次，仍失败则保留原文。
  6. **输出**：生成双语 ASS 存到视频旁 `<视频名>.zh-en.ass`：中文在上、字号大，原文在下、字号小；
     另存纯中文 SRT 方便别的播放器。播放时自动加载（`sub-auto=fuzzy` 已能匹配）。
  7. **模型与费用**：`Translator` 是接口，首个实现用 Claude API（默认 Claude Haiku 5.5，设置里可切 Sonnet 5.5；
     不急的任务可选 Batch 接口，费用减半但要等待）；API Key 由用户在设置页填写，只存本机，不进仓库和日志。
     任务开始前按字数估算 token 和费用并显示给用户确认；参考：45 分钟一集 Haiku 约 $0.01、Sonnet 约 $0.2。
- **验收**：
  - 单测：ASS 生成（时间轴、转义、双语样式）、翻译结果按 `id` 对齐、对齐失败重试与回退、
    缓存命中不再调用 API、Key 缺失时给出可读提示（全部用 `MockClient`，不访问真实 API）。
  - 手动（用户执行）：对一段 5 分钟英文片段跑通全流程，字幕时间轴准确、人名前后一致，
    实际花费与预估在同一数量级。

---

## M6 发布

### M6-1 安装包与文件关联 ✅
- **目标**：MSIX 或 Inno Setup 安装包，注册文件关联，卸载干净。
- **文件**：`installer/praxino.iss`（新建）或 `msix/`（新建）、`windows/runner/Runner.rc`、
  `.github/workflows/ci.yml`
- **做法**：按用户安装（不需要管理员）；注册 `HKCU\Software\Classes` 的视频关联和图标；
  检测/引导安装 VC++ 运行库；卸载时清理关联和缓存。
- **验收**：干净虚拟机安装 → 双击视频用 Praxino 打开 → 卸载后关联和安装目录都清理干净。

### M6-2 GitHub Release 自动发布 🟡

> 🟡 部分完成：本地 release、安装包、SHA256 已验证；GitHub tag 发布未执行。
- **目标**：打 tag 自动构建安装包并发布 Release。
- **文件**：`.github/workflows/release.yml`（新建）、`installer/`、`README.md`
- **做法**：tag `v*` 触发：`flutter analyze` + `flutter test` + `flutter build windows --release`
  + 生成安装包 + 上传 Release；附 SHA256 校验文件。
- **验收**：打一个测试 tag 后 Release 有安装包和校验文件；CI 全绿；校验和能对上。

### M6-3 自动更新检查 🟡

> 🟡 部分完成：Mock 覆盖更新检查；未用真实 GitHub Release 触发 UI 验证。
- **目标**：启动时检查新版本，提示用户去下载。
- **文件**：`lib/core/update/update_checker.dart`（新建）、`lib/ui/settings_page.dart`（修改）、
  `test/update_checker_test.dart`（新建）
- **做法**：请求 GitHub Releases API；semver 比较；支持"跳过这个版本"；失败静默；
  只提示，不自动下载安装。
- **验收**：`MockClient` 覆盖有新版本/无更新/网络错误；手动能弹出提示。

### M6-4 Android 端 ⛔

> ⛔ 不在当前范围：只做 Windows，不做 Android。
- **目标**：在架构不推翻的前提下跑通 Android 本地播放。
- **文件**：`android/`（新建）、`pubspec.yaml`、`lib/core/player/praxino_player.dart`（平台分支）、
  `lib/main.dart`、`.github/workflows/ci.yml`
- **做法**：生成 Android 工程；接入 media_kit 的 Android 库；文件选择用 SAF；
  触控播放控件；竖屏/横屏布局；不引入只在桌面可用的依赖（保持 core 接口不变）。
- **验收**：Android 模拟器/真机能播放 1080p 本地视频；`flutter analyze` / `flutter test` 通过；
  APK 能构建。

---

## M7 质量与验收

### M7-1 界面集成测试（integration_test） ⏳
- **目标**：用 Flutter 官方 `integration_test` 在应用内部驱动界面，替代隐藏桌面 + 模拟点击的方案。
- **文件**：`pubspec.yaml`（dev 依赖 `integration_test`）、`integration_test/*.dart`（新建）、
  `.github/workflows/ci.yml`
- **做法**：
  1. 覆盖主要流程：首页打开文件 → 播放页出现；增强菜单切换预设并持久化；设置页填写/保存凭据；
     订阅页添加 fixture 订阅 → 在线搜索出结果 → 选集；离线任务页排队/取消。
  2. 网络全部走注入的 `MockClient` / 本地 fixture；播放用仓库内一段几秒的自制测试视频
     （自己用 ffmpeg 生成色条，不用任何有版权的素材）。
  3. CI 上用 `flutter test integration_test -d windows` 运行（在 CI 机器上，不在用户桌面上）。
  4. 隐藏桌面的 `tool/hidden_*.ps1` 只保留做单实例/安装冒烟，不再扩展点击注入。
- **验收**：CI 上集成测试全绿；本地不弹窗即可运行（`--hidden` 仅 debug 生效）。

### M7-2 用户亲测清单 ⏳
- **目标**：目前所有界面验证都在隐藏窗口里完成，需要用户亲眼确认一次。
- **做法**：在 `docs/VERIFICATION.md` 里列一份勾选清单交给用户：本地播放/续播/选集、快捷键、增强菜单与 A/B 对比、
  外挂与在线字幕、弹幕显示、在线搜索与 3 个私有源实播、设置页、离线任务、安装/卸载与文件关联。
  用户发现的问题记成 GitHub issue，再拆成任务卡。
- **验收**：清单逐项有结果（通过/问题链接），没有"未验证"。
