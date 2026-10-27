# 交接说明

写给接手的开发者或 AI 代理。先读 `AGENTS.md`（规则）、`AGENTS.local.md`（本机路径，如果存在），
再读 `docs/ARCHITECTURE.md` 和 `docs/ROADMAP.md`。本文只讲**剩下什么、先做什么、哪里有坑**。

## 当前状态

- Windows 本地播放、Anime4K/FSRCNNX 实时超分、外挂/在线字幕、弹幕、在线源（Kazumi 规则、TVBox CMS、
  yt-dlp、Stremio、QuickJS 脚本）、离线 GPU 处理、安装包都已实现；CI 全绿（analyze + release 构建 + 全部测试）。
- **应用内实时补帧已打通**：mvtools（→ 约 60fps）和 RIFE（→ 2 倍帧率），掉帧自动降档并可撤销。
- **WebDAV / OpenList**：目录浏览、同目录播放列表与下一集、按“服务器 + 路径”续播、同目录字幕。
- **Jellyfin / Emby**：登录、媒体库/条目、Direct Play、中文字幕优先、进度上报与从服务器进度续播；完整海报墙还缺。
- **增强包一键安装**：多文件 manifest、SHA256、解压、自动填 Python/VapourSynth 路径；许可证结论见
  [`ENHANCE_PACK.md`](ENHANCE_PACK.md)。
- **AI 双语字幕**：本地 Whisper 识别 + Claude 分段翻译 + 双语 ASS/中文 SRT + 离线队列 + 费用确认；
  真实 Whisper/Claude 调用尚未验证。
- **Windows 集成测试**：`integration_test/app_test.dart` 6 条流程，本地隐藏桌面全过；CI 步骤已加，待推送验证。
- 已验证与未验证的项目逐条记在 [`VERIFICATION.md`](VERIFICATION.md)。

## 剩余工作（按建议顺序）

难度：★ 半天内　★★ 一两天　★★★ 需要调研或有外部依赖

| # | 任务 | 卡片 | 难度 | 说明 |
|---|---|---|---|---|
| 1 | WebDAV / OpenList 真实服务器验证 | M3-7 | ★★ | 代码完成；需要用户自己的 OpenList/WebDAV 地址，验证列表、续播、下一集、字幕和 401 提示 |
| 2 | Jellyfin 完整海报墙 | M3-8 | ★★ | 媒体库 UI 已有；缺按季/集分组的整页海报墙与图片缓存 |
| 3 | 真实 AI 字幕端到端 | M5-3 | ★★★ | 需要本机 Whisper 模型和付费 Claude Key；用 5 分钟英文片段核对时间轴、译名一致和费用 |
| 4 | 推送并确认 CI | M7-1 | ★ | 需要用户明确同意；重点确认 GitHub Actions 上 Windows 集成测试能建窗口 |
| 5 | 用户亲测清单 | M7-2 | ★ | 界面、补帧观感、快捷键、安装包等只能由用户亲眼确认 |
| 6 | GitHub Release 打 tag | M6-2 | ★ | 必须用户同意后执行 |

**需要用户参与的**（代理不要自己做）：
- 用户亲自看一遍界面和补帧画面（M7-2 清单）。
- 弹弹play 审核通过后，用户把 `DANDANPLAY_APP_ID` / `DANDANPLAY_APP_SECRET` 加到 GitHub Secrets。
- OpenSubtitles 真实账号下载、3 个私有源实播（M3-3）。
- 真实 WebDAV / Jellyfin 服务器、Whisper 模型和 Claude API Key。
- 推送 GitHub、第一次正式发布打 tag（M6-2），都必须用户同意。

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
9. **集成测试会创建真实窗口。** 代理不要直接 `flutter test integration_test -d windows`；
   用独立桌面运行（可复用 `tool/hidden_smoke.ps1` 的 CreateDesktop 思路），或交给 CI。
10. **Claude 模型 id 只是设置项。** 默认 `claude-haiku-5-5` / `claude-sonnet-5-5` 必须按账号实际可用模型核对；
    费用估算按字数粗略计算，真实费用以 API 账单为准，任务开始前的确认对话框不是账单承诺。

## 杂项

- 本地分支 `backup/pre-rewrite`、`backup/pre-squash` 是历史改写前的备份，**不要推送**；确认无用后删除。
- 测试 QuickJS 需要先构建，并设置 `FLUTTER_QJS_NEXT_LIBRARY` 指向构建出的 `flutter_qjs_next_plugin.dll`
  （CI 已这样做）。
