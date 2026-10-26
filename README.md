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
| 在线源：可选兼容 Kazumi 规则（搜索、选集） | 🚧 |
| 在线源：yt-dlp、TVBox（CMS 接口）、Stremio addon、脚本源 | ⏳ |
| 弹幕（弹弹play） | ⏳ |
| 实时补帧（RIFE / mvtools，通过 VapourSynth） | ⏳ |
| 离线超分 / 补帧（Real-ESRGAN、RIFE ncnn） | ⏳ |

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

开发规范见 [AGENTS.md](AGENTS.md)，架构说明见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 致谢

- [mpv](https://mpv.io) 和 [media_kit](https://github.com/media-kit/media-kit)：播放内核
- [Anime4K](https://github.com/bloc97/Anime4K)（MIT）：实时超分着色器
- [Kazumi](https://github.com/Predidit/Kazumi)：规则格式兼容性的参考；本项目不复制其代码

## 许可证

[GPL-3.0](LICENSE)。第三方资源的许可证放在各自的目录里。
