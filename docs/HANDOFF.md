# 交接说明

写给接手的开发者或 AI 代理。先读 `AGENTS.md`（规则）、`AGENTS.local.md`（本机路径，如果存在），
再读 `docs/ARCHITECTURE.md` 和 `docs/ROADMAP.md`。本文只讲**剩下什么、先做什么、哪里有坑**。

## 当前状态

- Windows 本地播放、Anime4K/FSRCNNX 实时超分、外挂/在线字幕、弹幕、在线源（Kazumi 规则、TVBox CMS、
  yt-dlp、Stremio、QuickJS 脚本）、离线 GPU 处理、安装包都已实现；CI 全绿（analyze + release 构建 + 全部测试）。
- **应用内实时补帧已打通**：mvtools（→ 约 60fps）和 RIFE（→ 2 倍帧率），1080p 在 RTX 5080 上实测不掉帧。
- 已验证与未验证的项目逐条记在 `docs/VERIFICATION.md`，以它为准。

## 剩余工作（按建议顺序）

难度：★ 半天内　★★ 一两天　★★★ 需要调研或有外部依赖

| # | 任务 | 卡片 | 难度 | 说明 |
|---|---|---|---|---|
| 1 | 补帧掉帧提示与自动降档 | M2-3 第 5 步 | ★ | 复用 `EnhanceAdvisor`（M2-2 已有超分降档）：采样 `frame-drop-count`，持续增长时 RIFE → mvtools → 关，并弹出可撤销的提示。纯逻辑先写单测 |
| 2 | 安装包回归 | M6-1 | ★ | `windows/CMakeLists.txt` 已不再安装 ANGLE 附带的 `vulkan-1.dll` / `vk_swiftshader.dll`；重新打一次安装包，确认安装目录里没有这两个文件、普通播放正常、"启用增强包"能在安装目录里替换 libmpv |
| 3 | 增强包一键安装 | M2-3 | ★★★ | 现在只有 libmpv 能按 manifest 下载，VapourSynth 运行时要手动放。需要：一个 manifest 描述多个文件（libmpv、便携 Python、VapourSynth R81、mvtools、`librife.dll`、RIFE v4.6 模型）、SHA256 校验、解压、自动填好设置里的两个路径。**许可证要逐个核对**（Python PSF、VapourSynth LGPL、mvtools GPL、RIFE-ncnn-Vulkan 与模型 MIT），确定能否由我们托管再分发；不能就改为引导用户从官方地址下载 |
| 4 | 较弱显卡的 RIFE | M2-3 | ★★ | 设置里提供 RIFE 档位：2 倍 / 固定 60fps；可选 `uhd=True`、lite 模型。弱显卡默认 mvtools |
| 5 | WebDAV / OpenList 源 | M3-7 | ★★ | 卡片里步骤完整。凭据只放请求头和本机设置 |
| 6 | Jellyfin / Emby | M3-8 | ★★ | 优先 Direct Play，才能发挥超分 |
| 7 | 界面集成测试 | M7-1 | ★★ | 用 `integration_test`，在 CI 上跑；测试视频用 ffmpeg 自己生成色条 |
| 8 | AI 双语字幕 | M5-3 | ★★★ | 本地 Whisper + 大模型分段翻译；难点是按句对齐、术语一致、费用预估和缓存 |

**需要用户参与的**（代理不要自己做）：
- 用户亲自看一遍界面和补帧画面（M7-2 清单）。
- 弹弹play 审核通过后，用户把 `DANDANPLAY_APP_ID` / `DANDANPLAY_APP_SECRET` 加到 GitHub Secrets。
- OpenSubtitles 真实账号下载、3 个私有源实播（M3-3）。
- 第一次正式发布打 tag（M6-2），必须用户同意。

## 已经踩过的坑（不要重新踩）

1. **进程里只能有一份 libmpv。** 视频插件按名字导入应用目录的 `libmpv-2.dll`，所以增强包是"替换"那个文件
   （`EnhancePackActivation`），**不要**用 `MediaKit.ensureInitialized(libmpv: ...)`。
   之前"client API 2.6 不兼容、需要 2.1"的结论是误判。
2. **应用目录里不能有 ANGLE 附带的开发版 `vulkan-1.dll`。** 否则 RIFE（ncnn）一初始化就在 NVIDIA 驱动里崩溃。
   CMake 已排除；升级 media_kit 后要重新检查。
3. **环境变量要写两份。** 进程运行中设置 `PYTHONPATH` 等，必须同时写 Win32 环境块和 C 运行时的表
   （`VapourSynthRuntime`），否则 Python 读不到。
4. **VapourSynth R81 不再接受 API 3 插件。** vs-mlrt 目前的 Windows 插件都是 API 3，不能用；
   vs-rife 需要数 GB 的 CUDA PyTorch。现在用的是 VapourSynth-RIFE-ncnn-Vulkan。
5. **RIFE 补到固定 60fps 太重**：每 5 帧要推理 4 帧，RTX 5080 上 1080p 只有约 40fps。模板默认 2 倍。
6. **不要在用户桌面弹窗。** 验证播放器用隐藏桌面 + `--hidden`（只在 debug 生效）+ `PRAXINO_DIAG_LOG`
   （debug 构建会写 mpv 日志、`<路径>.mpv.log` 完整日志和每 2 秒的 `[stats]` 行）。具体做法见 `AGENTS.local.md`。
   崩溃时用 Sysinternals ProcDump（`-e -ma -w praxino.exe`）抓转储。
7. **推送前做隐私扫描。** 曾经在 `tool/` 脚本里扫出写死的本机路径和视频文件名。至少检查：
   盘符路径、用户名、邮箱、密钥、真实站点域名。公开文档只写通用说明，本机细节放 `AGENTS.local.md`。
8. **同一时间只让一个会话写这个仓库。**

## 杂项

- 本地分支 `backup/pre-rewrite`、`backup/pre-squash` 是历史改写前的备份，**不要推送**；确认无用后删除。
- 测试 QuickJS 需要先构建，并设置 `FLUTTER_QJS_NEXT_LIBRARY` 指向构建出的 `flutter_qjs_next_plugin.dll`
  （CI 已这样做）。
