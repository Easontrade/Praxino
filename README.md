# Praxino

一个可以随意改造的视频播放器：本地播放、实时 AI 超分与补帧、开放的在线源规则、弹幕和字幕。

> 名字取自 1877 年的 Praxinoscope（活动视镜）。它用镜子让动画第一次变得清晰明亮，后来还在巴黎完成了第一场公开的动画放映。

**状态**：早期开发，目前只有 Windows 版。路线图见 [docs/ROADMAP.md](docs/ROADMAP.md)。

## 功能

| | 状态 |
|---|---|
| 本地播放：拖入即播、同目录自动生成播放列表、最近播放 | ✅ |
| 字幕：同名字幕自动加载、外挂字幕、ASS 特效（libass） | ✅ |
| 实时超分：Anime4K 三档，以及去色带、降噪 | ✅ |
| 在线源：Kazumi 规则（搜索、选集） | ✅ |
| 源排行：搜索后自动检测，一键播放最佳源 | ✅ |
| 在线源：yt-dlp、TVBox（CMS 接口）、Stremio addon、脚本源 | ✅（真实站点需自行验证） |
| 弹幕（[弹弹play 开放弹幕网络](https://www.dandanplay.com/open.html)） | ✅（正式构建已内置凭证，也可在设置页自填） |
| 实时补帧（RIFE / mvtools，通过 VapourSynth） | ✅（需安装[增强包](docs/ENHANCE_PACK.md)） |
| 离线超分 / 补帧（Real-ESRGAN、RIFE ncnn） | ✅ |
| WebDAV / OpenList | ✅（真实服务器需自行验证） |
| Jellyfin / Emby 媒体库 | 🚧（海报墙待补） |
| AI 双语字幕（本地 Whisper + DeepSeek） | 🚧（管线完成，真实模型与 API 待验证） |

## 快捷键

| 键 | 功能 |
|---|---|
| `Ctrl+0` / `1` / `2` / `3` | 超分：关 / 流畅 / 均衡 / 高质量 |
| `Ctrl+E` | 画质修复（去色带 + 降噪）开关 |
| 空格、←/→、F | 暂停、快退/快进、全屏 |

## 关于在线源

Praxino 只是**播放器和规则引擎**，不内置、不托管、也不推荐任何视频源。
所有在线内容都来自用户自己添加的第三方订阅，与本项目无关。请遵守你所在地区的法律，并尊重版权。

## 构建

需要 Flutter 3.47 和 Visual Studio 2022 Build Tools（勾选 C++ 桌面开发）。

```
flutter pub get
flutter run -d windows
```

想在本地构建里直接内置弹幕凭证（免去用户自己填 AppId/Secret），先设置环境变量再打包：

```
$env:PRAXINO_DANDAN_APP_ID = '<AppId>'
$env:PRAXINO_DANDAN_APP_SECRET = '<AppSecret>'
.\tool\release_local.ps1 -Version 1.0.0
```

凭证只以 `--dart-define` 的形式在构建时注入（base64 编码，仓库里不留明文）；不设这两个变量时，
安装包仍然可用，用户需要在设置页里自己填。凭证是否有效可以直接对着开放接口自检，不需要启动播放器：
`.\tool\check_dandanplay.ps1` 用环境变量里的凭证发一次签名请求，
`dart run tool/check_dandanplay.dart` 走的则是播放器自己用的那份客户端。

开发规范见 [AGENTS.md](AGENTS.md)，架构说明见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 致谢

- [mpv](https://mpv.io) 和 [media_kit](https://github.com/media-kit/media-kit)：播放内核
- [Anime4K](https://github.com/bloc97/Anime4K)（MIT）：实时超分着色器
- [Kazumi](https://github.com/Predidit/Kazumi)：规则格式兼容性的参考；本项目不复制其代码
- [弹弹play 开放弹幕网络](https://www.dandanplay.com/open.html)：弹幕搜索与弹幕内容由该平台提供。
  Praxino 是开源软件（GPL-3.0），按开放平台的接口规范接入，不转存、不再分发其弹幕库；
  弹幕内容的著作权归原作者与弹弹play 所有。

## 许可证

[GPL-3.0](LICENSE)。第三方资源的许可证放在各自的目录里。



