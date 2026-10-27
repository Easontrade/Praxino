# Praxino 架构与设计

> 名字来自 1877 年的 **Praxinoscope（活动视镜）**：它用镜子代替西洋镜的窄缝，让动画第一次变得清晰明亮；
> 发明者 Reynaud 后来用它在巴黎做了世界上第一场公开放映的动画。清晰的画面 + 放映，正是这个项目要做的事。

本文档是所有实现工作的依据。改动架构前先改这份文档。

---

## 1. 目标与非目标

**目标**（按优先级）

1. **本地播放做到最好**：拖进来就能播，同目录自动成播放列表，字幕/音轨自动选对，续播。
2. **画质增强**：实时超分（GLSL 着色器）→ 实时补帧（VapourSynth/RIFE）→ 离线高质量处理（Real-ESRGAN/RIFE ncnn）。
3. **开放的在线源**：可选兼容现有社区规则生态（Kazumi 规则、TVBox、Stremio、yt-dlp），播放器本身**不内置任何源**。
4. **弹幕和字幕**：本地文件和在线剧集都能匹配弹幕；外挂字幕、在线字幕搜索。
5. **可长期维护**：模块边界清晰、核心逻辑有单元测试、CI 自动构建。

**非目标**

- 不做 DRM 内容播放、不绕过任何付费墙。
- 不在仓库里放任何真实视频站点的地址或规则（只放规范和用 `example.test` 的示例）。
- 第一阶段不做移动端（架构上不阻断，Flutter 以后可以直接加 Android）。

---

## 2. 技术选型与理由

| 层 | 选择 | 为什么 |
|---|---|---|
| UI | Flutter 3.47 (Dart 3.13) | 一套代码覆盖桌面和移动端；Kazumi 等项目已经验证过 Flutter + mpv 这条路 |
| 播放内核 | libmpv，经 `media_kit` 调用 | mpv 是唯一同时具备 GLSL 着色器钩子、VapourSynth 滤镜、libass 的成熟内核 |
| 视频渲染 | `media_kit_video`（D3D11 → ANGLE 纹理） | 视频作为 Flutter 纹理，UI 可以任意叠加（弹幕、菜单） |
| 实时超分 | Anime4K GLSL（已内置），后续加 ArtCNN / FSRCNNX | 任何 GPU 都能跑，不依赖 CUDA |
| 补帧 | VapourSynth + vs-rife (TensorRT) / mvtools | 需要自带 libmpv，见 §5.2 |
| 规则解析 | `html` + `xpath_selector_html_parser`、`json_path` | 兼容 Kazumi 规则的字段语义（只做格式解析，不复制它的代码） |
| 本地存储 | 现在 `shared_preferences`；M3 起换 `drift`(SQLite) | 观看历史、订阅、匹配缓存需要查询能力 |
| 许可证 | **GPL-3.0** | 分发链接 libmpv 的二进制时整体必须兼容 GPL（mpv 是 GPLv2+，GPL-3.0 允许这种组合）；libass 是 ISC。Kazumi 代码不参与本项目实现 |

---

## 3. 目录结构

```
lib/
  main.dart                     入口：初始化 media_kit，读取设置，处理命令行参数
  core/                         与 UI 无关的逻辑（除 player 封装外都可单测）
    player/praxino_player.dart  唯一接触 mpv 的地方
    enhance/enhance_settings.dart  画质增强的纯数据模型 → mpv 属性
    library/local_files.dart    本地文件识别、同目录剧集、自然排序
    settings/settings_store.dart  持久化设置
    settings/keybindings.dart    动作 → 默认按键 + 序列化（待实现，M1-7）
    sources/
      source_adapter.dart       在线源统一接口（所有适配器都实现它）
      kazumi/                   Kazumi 规则适配器（可选）
      (tvbox/ stremio/ ytdlp/ script/   ← 待实现)
    danmaku/                    (待实现) 弹幕提供者 + 匹配
    subtitles/                  (待实现) 在线字幕搜索
  ui/                           页面和组件，只调用 core/
assets/shaders/anime4k/         Anime4K v4 着色器（MIT，见同目录 LICENSE）
test/                           单元测试，镜像 lib/core 的结构
docs/                           架构与路线图
```

**分层规则（必须遵守）**

1. `ui/` 可以依赖 `core/`；`core/` **绝不** import `package:flutter/material.dart` 或任何 `ui/` 文件
   （`praxino_player.dart` 例外地依赖 `foundation.dart` 的 `ValueNotifier`/`kDebugMode`）。
2. 只有 `core/player/` 可以调用 `NativePlayer.setProperty` / `command`。其它地方要改 mpv 行为，就给 `PraxinoPlayer` 加方法。
3. 所有"把配置翻译成 mpv 属性"的逻辑写成**纯函数**（参考 `EnhanceSettings.toMpvProperties`），这样不用启动播放器就能测试。
4. 网络请求一律通过可注入的 `http.Client`，测试用 `MockClient`，**测试里不访问真实网络**。

---

## 4. 播放内核层（`core/player`）

```
UI ──► PraxinoPlayer ──► media_kit Player ──► libmpv
            │                                   ▲
            ├─ kMpvBaseline（启动时一次性写入） ─┘
            └─ setEnhance(EnhanceSettings) → toMpvProperties() → setProperty×N
```

- **kMpvBaseline** 参考作者自用的 mpv.conf：`sub-auto=fuzzy`、字幕语言优先级 `zh-Hans > … > en`、
  512MiB 前向缓存、`keep-open` 等。新增全局默认值加在这里。
- **播放列表**：打开本地文件时用 `siblingVideos()` 把同目录视频按自然排序（EP2 < EP10）组成 `Playlist`，
  上一集/下一集由 media_kit 原生处理。
- **libass 开启**（`PlayerConfiguration.libass: true`）：ASS 特效字幕由 mpv 渲染进视频帧，
  所以字幕**会**经过超分着色器之后的缩放，但不会被 Anime4K 处理（Anime4K 钩在 MAIN 纹理上，字幕在 OSD 层）。
- **快捷键**：动作集中在一张表里（动作 → 按键），后续不要在 `build` 里散落 `SingleActivator`；
  M1-7 把这张表接到设置页，允许用户改键并持久化。
- **已知无害日志**：`property not found _setProperty(osc, 1)`（media_kit 自身）、
  `dxva2-egl Failed to create EGL surface`（回退到 D3D11 纹理，正常）。
- **MP4 数据轨与 NAL 报错（M1-6 结论）**：无窗口复现不了。独立 mpv 0.41、media_kit 自带的
  libmpv 0.36（FFmpeg n6.0，`vo=null`/`ao=null`）和 ffmpeg 直接解码同一文件都没有
  `Invalid NAL unit size` / `missing picture in access unit`。此前日志可能来自旧构建或特定渲染路径；
  再遇到时先记录 libmpv 版本，并对比 `hwdec=no` 与 `vid=no`。

---

## 5. 画质增强（`core/enhance`）

增强分三级，互不依赖。L1 与 L2 可以同时开启，但两者都写 mpv 的 `vf`，
所以实现 L2 时必须把降噪和 VapourSynth 合并成一条滤镜链，不能各写各的；L3 是离线处理，
产物再用播放器打开。

### 5.1 L1 实时着色器（✅ 已实现）

`EnhanceSettings` = { 超分预设, 去色带, 降噪 } → mpv 属性：

| 设置 | mpv 属性 |
|---|---|
| 超分预设 | `glsl-shaders` = 着色器绝对路径用 `;` 连接（运行时目录 `<exe>/data/flutter_assets/assets/shaders/anime4k`） |
| 去色带 | `deband=yes` + iterations 2 / threshold 40 / grain 16 |
| 降噪 | `vf=lavfi=[hqdn3d=1.2:1.0:6:6]`，同时 `hwdec=auto-copy`（lavfi 需要帧在内存里） |

三档预设都按官方 Mode A 的结构排列（Clamp → Restore → Upscale → AutoDownscalePre x2/x4 → Upscale）；
第一段用 CNN-S / M / VL，第二段分别用 S / S / M 以降低开销。设置持久化，
**换集、换文件都保持**（本项目自己维护的设置状态，不依赖外部播放器）。
快捷键：`Ctrl+0~3` 切预设（本项目新增），`Ctrl+E` 切画质修复（沿用作者 mpv 的 enhance-toggle 习惯）。

**扩展方式**：新增预设 = 在 `UpscalePreset` 加一个枚举值 + 着色器文件放进 `assets/shaders/<family>/`；
换着色器家族时还要让 `PraxinoPlayer` 按预设选目录（当前 `shaderDirectory` 写死了 `anime4k`，M2-1 会改）。
真人片建议加 ArtCNN 或 FSRCNNX（Anime4K 是为动画线条设计的，对实拍会涂抹）。

### 5.2 L2 实时补帧（🟡 M2-3：mvtools 与 RIFE 应用内均已验证）

mpv 用 `vf=vapoursynth=<script.vpy>` 跑 VapourSynth 脚本。问题：据目前使用的 media_kit 发行包，
自带的 libmpv 没有编译 VapourSynth 支持（M2-3 第一步先验证；如果其实支持，就省掉增强包）。方案：

1. 做一个可选的"增强包"（不进安装包，首次使用时下载到 `%APPDATA%/Praxino/enhance-pack/`）：
   带 VapourSynth 的 `libmpv-2.dll`（shinchiro 的构建）+ 便携 Python + VapourSynth（R81）
   + `mvtools` + VapourSynth-RIFE-ncnn-Vulkan（`librife.dll`，MIT）和 RIFE v4.6 模型
   （放在 `<vapoursynth>/plugins/models/rife-v4.6`，模板按这个相对位置找，也可用 `PRAXINO_RIFE_MODEL` 覆盖）。
   不用 vs-mlrt（Windows 插件仍是 VapourSynth API 3，R81 已拒绝加载）和 vs-rife（要数 GB 的 CUDA PyTorch）。
2. **增强包必须替换应用目录里的 `libmpv-2.dll`，不能另外加载一份。**
   `media_kit_video_plugin.dll` 按名字直接导入 `libmpv-2.dll`，Windows 在 `main()` 之前就从应用目录加载它；
   如果再用 `MediaKit.ensureInitialized(libmpv: '<其它路径>')`，进程里会有两份 libmpv——播放器由一份创建、
   由另一份渲染，直接访问冲突崩溃（0xC0000005），与 client API 版本无关（2.1 和 2.6 都一样）。
   所以“启用”= 把自带 DLL 改名为 `libmpv-2.media_kit.dll` 备份、复制增强包 DLL 为 `libmpv-2.dll`
   （Windows 允许给已加载的 DLL 改名，所以运行中就能操作），重启生效；“停用”反向恢复。
   见 `EnhancePackActivation`。兼容条件只要求 client API 主版本 2、次版本 ≥ 1。
   VapourSynth 运行时（便携 Python + `site-packages/vapoursynth`）的路径在设置页填写，启动时由
   `VapourSynthRuntime` 写入进程环境——要同时写 Win32 环境块和 C 运行时的环境表，
   否则 Python 读不到 `PYTHONPATH`。
   **一键安装**：`EnhancePackBundle` 用一个 manifest 描述多个组件（libmpv、便携 Python、
   VapourSynth wheel、mvtools、librife、RIFE 模型），每项带 SHA256 和许可证；
   `EnhancePackInstaller` 校验后解压到 `%APPDATA%/Praxino/enhance-pack/`，拒绝绝对路径和
   `..` 穿越，再按“`python3xx.dll` 所在目录”和“同时含 `vsscript.dll` + `vapoursynth.pyd` 的目录”
   自动填好两个路径。仓库不托管第三方二进制，manifest 指向官方发布地址；许可证结论见
   [`ENHANCE_PACK.md`](ENHANCE_PACK.md)。
3. `EnhanceSettings.interpolation`：`off / mvtools(轻量,CPU) / rife(GPU)`。每种模式默认用
   `assets/vapoursynth/` 里的内置模板（`interpolationScriptFor`），设置里的自定义 `.vpy` 只作覆盖。
   生成的 vf 要和 L1 的 hqdn3d 合并成一条链（见本节开头），不能直接覆盖 `vf`。
   mvtools 模板输出约 60fps；RIFE 模板输出**2 倍帧率**——固定 60fps 需要每 5 帧推理 4 帧，
   RTX 5080 上 1080p 只有约 40fps 吞吐（GPU 100%），2 倍约 60fps，实时有余量。
4. **应用目录里不能有 media_kit ANGLE 包附带的开发版 `vulkan-1.dll` / `vk_swiftshader.dll`。**
   Python 初始化后进程进入"安全 DLL 搜索"模式，此后按名字加载 `vulkan-1.dll` 会先命中应用目录里的那份，
   即使系统版已经加载；进程里两个 Vulkan 加载器同时存在，RIFE（ncnn）一初始化就在 NVIDIA 驱动
   `nvoglv64.dll` 里写入开发版加载器的内存而崩溃（崩溃转储确认）。media_kit 只用 ANGLE 的 D3D11 后端，
   所以 `windows/CMakeLists.txt` 把这两个文件从安装列表里排除，并删除旧构建残留；
   `VapourSynthRuntime` 也会先按完整路径预加载系统 `vulkan-1.dll`。
5. RIFE 很吃显卡。UI 要显示实际掉帧数（mpv 属性 `frame-drop-count`、`vo-delayed-frame-count`），
   掉帧时提示降档（⏳ M2-3 第 5 步）。

### 5.3 L3 离线处理（✅ M5-2；M5-3 复用同一队列）

"先处理再看"：ffmpeg 解码 → Real-ESRGAN-ncnn-vulkan / RIFE-ncnn-vulkan → ffmpeg 编码 → 输出新文件。
做成后台任务队列（可暂停、断点续做），和播放器解耦。

队列只有一个 `OfflineProcessor`，`RoutingOfflineProcessor` 按 `OfflineJobKind` 分派：
`enhance` 走超分/补帧，`aiSubtitle` 走 AI 双语字幕（见 §7.2）。旧版本持久化的任务没有 `type` 字段，
读回时按 `enhance` 处理。

---

## 6. 在线源系统（`core/sources`）

### 6.1 核心思想

- **一个接口，多种适配器。** UI 只认 `SourceAdapter`（`search` → `episodes` → `resolve`）。
- **核心不依赖具体格式**：`SourceAdapter`、`MediaSummary`、`Episode` 等内部模型是自有的；
  Kazumi、TVBox、Stremio 都只是适配器，删掉任何一个都不影响其它源。
- **适配器只负责翻译格式**，不关心 UI；新格式 = 新目录 + 实现接口 + 测试，不碰其它代码。
- **订阅而不内置**：用户填一个订阅地址（JSON 索引），里面列出若干规则；我们下载、校验、缓存。

```
           ┌─────────── SourceRegistry（M3）───────────┐
订阅 URL ──► 下载/解析 ──► KazumiRuleAdapter ×N        │
           │              TvBoxAdapter ×N              │──► 聚合搜索 ──► 排序 ──► UI
           │              StremioAdapter ×N            │
           │              YtDlpAdapter（单例）          │
           └───────────────────────────────────────────┘
                     resolve() == null ?
                           │ yes
                           ▼
                   StreamSniffer（WebView2 抓 m3u8/mp4 请求）──► PlayableStream ──► PraxinoPlayer.open(url, headers)
```

### 6.2 数据模型（`source_adapter.dart`）

| 类型 | 含义 |
|---|---|
| `MediaSummary` | 一条搜索结果（标题、详情页定位、来源 id） |
| `EpisodeGroup` | 一条"线路"，含若干 `Episode` |
| `Episode` | 一集（名字、播放页定位） |
| `PlayableStream` | mpv 能直接打开的地址 + 请求头（Referer/UA/Cookie），可选带 width/height/bitrateKbps/subtitleLanguages/subtitleUrls 供画质与字幕选择；yt-dlp 字幕优先中文 |
| `StreamSniffer` | 播放页需要执行 JS 才能拿到流地址时，用浏览器加载并抓取请求 |

### 6.3 适配器清单

| 适配器 | 状态 | 说明 |
|---|---|---|
| Kazumi 规则 | ✅ xpath + api(nested) 搜索与选集；直链规则直接 resolve，`useWebview` 规则返回 null 交给 Sniffer（⏳ M3-3） | 只做格式兼容，不复制 Kazumi 代码；未知字段忽略以兼容新版本 |
| yt-dlp | ⏳ M3 | 调用 `yt-dlp -J <url>` 拿直链和请求头；覆盖 YouTube、B 站等上千站点 |
| TVBox / CatVod | ⏳ M3 | 只支持 `type 0/1`（苹果 CMS 的 XML/JSON 接口），**不执行** JAR/Python 爬虫（安全原因） |
| Stremio addon | ⏳ M4 | HTTP 协议：`/manifest.json`、`/catalog`、`/meta`、`/stream` |
| 脚本源 | ⏳ M4 | QuickJS 沙箱，只暴露 `fetch`/`parseHtml`/`log`，限时限内存 |

### 6.4 可靠性策略（自己实现）

这些策略参考了社区播放器的常见做法，但算法、数据结构和接口都由本项目自己设计，
不复制、不移植任何外部代码：

- **标题匹配排序**：搜索结果按"标题相似度 + 季数匹配"排序，最优的先探测。
- **源探测**：对候选结果并发做轻量探测（能否拿到流、首包延迟），自动选可用且最快的。
- **故障切换**：播放中报错/卡死超过阈值 → 自动切下一个可用源，保持进度。
- **预取下一集**：当前集播到一定进度时，提前解析下一集的流地址；临近结束再刷新一次（防止签名过期）。

---

## 7. 弹幕与字幕

### 7.1 弹幕（⏳ M4）

- `DanmakuProvider` 接口：`match(MediaKey) → List<DanmakuEpisode>`、`fetch(episodeId) → List<DanmakuItem>`。
- 首个提供者：**弹弹play 开放平台 API**（需要申请 AppId/AppSecret，从环境变量或用户设置读取，**不提交到仓库**）。
  - 本地文件：按"文件前 16MB 的 MD5 + 文件名 + 大小"匹配。
  - 在线剧集：按"番剧标题 + 集数"搜索。用户手动选过的匹配结果按剧记住（本项目自己实现的匹配记忆）。
- 渲染：在 `Video` 之上叠一层 Flutter 画布（可用 `canvas_danmaku` 包，或自写 `CustomPainter`）。
  **弹幕不进 mpv**，这样不会被超分处理，也不影响截图里的画面。
- 设置：透明度、字号、显示区域、屏蔽词、密度上限、时间偏移。

### 7.2 字幕

- ✅ 自动加载同名/子目录字幕（`sub-auto=fuzzy`）、拖入或按钮加载外挂字幕、libass 渲染。
- ⏳ 在线搜索：ASSRT（射手）与 OpenSubtitles，结果下载到视频同目录的 `subs/` 后加载。
- ⏳ 字幕时间偏移快捷键（`z`/`x` 是 mpv 默认键，需要在 UI 层补提示）。
- 🟡 **AI 双语字幕**（M5-3，`lib/core/subtitles/ai/`）：大模型不接收音频，所以分两步——
  本地 Whisper 识别出带时间轴的原文（`transcriber.dart`，whisper.cpp 或 faster-whisper 命令行，
  只传参数列表不拼 shell），再由 `Translator` 接口分段翻译（`deepseek_translator.dart`，默认
  DeepSeek Chat，设置里可切 DeepSeek Reasoner，API 地址也可改）。
  - 数据模型：`TranscriptSegment {id,start,end,text}`；翻译结果按 `id` 对齐，模型漏掉的 id
    重试一次，仍失败就回填原文（`TranslationResult.fallbackIds`）。
  - 术语表：整集字幕先发一次给模型抽取人名/专有名词的固定译法，后续每个批次都带上。
  - 分段：每批约 40 句，附前后各 5 句只读上下文（`buildTranslationBatches`）。
  - 输出：视频旁 `<视频名>.zh-en.ass`（中文在上、字号大，原文在下、字号小，两条 Dialogue
    共用时间轴）与 `<视频名>.zh.srt`（纯中文）。ASS 文本转义 `\`、`{}` 和换行；逗号留在
    Dialogue 的最后一个字段里，不需要转义。
  - 费用：`estimateTranslationCost` 按字数和批次数粗略估算 token 与美元，队列在真正调用 API 前
    通过 `confirmEstimate` 回调让用户确认。
  - 缓存：`%LOCALAPPDATA%/Praxino/ai-subtitles/<sha256(绝对路径|大小|mtime)>.json` 存
    transcript + 译文，命中时只重写输出文件，不再调用 Whisper/API；损坏的缓存忽略。
  - 作为离线队列里的 `aiSubtitle` 任务运行；API Key 只存本机设置，不写日志、不进仓库。
  片源字幕的现状：站点源多为**硬字幕**（压在画面里，不需要也无法替换）；yt-dlp 能拿到软字幕轨；
  本地 MKV 常内封软字幕。所以在线搜索和 AI 生成主要服务本地、网盘和媒体服务器片源。

### 7.3 自有片源（⏳ M3-7 / M3-8）

除了站点规则，Praxino 把"播放用户自己的文件"作为一等来源：WebDAV / OpenList（把各家网盘挂成 WebDAV）
和 Jellyfin / Emby 媒体服务器都实现为 `SourceAdapter`。它们的片源通常是原盘或高码率文件，
能真正发挥超分和补帧的价值；认证信息只放在请求头和本机设置里，不拼进 URL、不写日志。

WebDAV 的"下一集"和本地文件走同一条路：把同目录视频按自然顺序交给 `PlayerPage.sources`，
mpv 的原生下一集/自动续集就能用。续播复用 `WatchHistory`，但 key 由 `webDavHistoryKey` 生成
（去掉 URL 里的 userinfo、query 和末尾斜杠，再加 `webdav:` 前缀），因此同一台服务器上的同一路径
在换 token、带不带查询参数时都能命中，也不会把密码写进历史记录。远程 URL 默认不记历史，
只有打开方显式传入 `historyKeyFor` 才记录；Jellyfin 的续播用服务器进度，不走这条。

---

## 8. 历史资产（不在仓库里）

维护者在仓库外保留了一份私有对照资料（旧实现、手动测试用的规则、mpv 配置），
位置和清单写在不提交的 `AGENTS.local.md` 里。**不要把其中任何内容提交到 Git**，里面有第三方站点信息。

这些资料只做**行为对照**和手动测试，**不是实现依赖**；本项目不复制、不移植其中的代码，
所有逻辑按本文档自己设计。

> 为什么还留着：用来对照交互和做手动测试。但实现必须能从本文档推导出来；
> 读代码的人不应该需要打开这些私有资料才能理解 Praxino。

---

## 9. 法律与仓库政策

1. 仓库里不出现任何真实视频站点的域名、规则、API Key。示例统一用 `example.test`。
2. README 写明：本软件是播放器和规则引擎，内容由用户自行订阅的第三方提供，与本项目无关。
3. 第三方组件的许可证随资源放置（例如 `assets/shaders/anime4k/LICENSE`），并在 README 致谢。
4. 收到 DMCA 或其它下架请求：删除对应的**示例或文档**即可；因为本来就不内置源，核心代码不受影响。

