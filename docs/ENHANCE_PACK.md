# 增强包一键安装（M2-3）

播放器自带的 libmpv 没有编译 VapourSynth，所以实时补帧（mvtools / RIFE）需要换一套运行时。
增强包就是这组可选文件；它安装到 `%APPDATA%\Praxino\enhance-pack\`，不进安装包，也不上传到仓库。

## 组成

| 组件 | 用途 | 建议来源 |
|---|---|---|
| `libmpv-2.dll` | 带 VapourSynth 支持的 mpv（shinchiro 构建，client API 2.x） | shinchiro 的官方 Windows 构建 |
| 便携 Python | 给 VapourSynth 提供 Python 运行时 | python.org 的 Windows embeddable zip |
| VapourSynth R81 | 核心、`vspipe`、VSScript | VapourSynth 官方 release / wheel |
| mvtools | 运动补偿补帧插件（`plugins/mvtools.dll`） | mvtools 官方 release |
| `librife.dll` | RIFE ncnn 的 VapourSynth 插件（API 4） | VapourSynth-RIFE-ncnn-Vulkan release |
| RIFE v4.6 模型 | `plugins/models/rife-v4.6/` | RIFE-ncnn-Vulkan release |

不要用 vs-mlrt 的 Windows 插件（仍是 VapourSynth API 3，R81 拒绝加载），也不要用 vs-rife
（需要数 GB 的 CUDA PyTorch）。

## 使用流程

1. 打开“设置 → 增强包 / 补帧”。
2. 在文本框里粘贴 **manifest URL** 或 **manifest JSON**。
3. 确认弹窗里列出的组件和许可证。
4. 安装器逐个下载、校验 SHA256、解压到增强包目录，再自动找到 Python 和
   `site-packages\vapoursynth` 两个路径填进设置；如果包含 libmpv，会替换应用目录里的
   `libmpv-2.dll`（原文件备份为 `libmpv-2.media_kit.dll`），**重启后生效**。
5. 重启后到播放页打开“补帧”，选择 mvtools 或 RIFE。

旧式单文件 manifest（只有 `url`/`sha256`/`fileName`）仍然可用，但只会下载 libmpv，
需要手动填写 VapourSynth 路径。

## manifest 格式

```json
{
  "version": "r81-2026.10",
  "name": "Praxino 增强包（VapourSynth + RIFE）",
  "files": [
    {
      "name": "libmpv（含 VapourSynth）",
      "url": "https://example.test/mpv/libmpv-2.dll",
      "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      "fileName": "libmpv-2.dll",
      "license": "GPL-2.0-or-later",
      "licenseUrl": "https://example.test/mpv/LICENSE"
    },
    {
      "name": "便携 Python 3.12",
      "url": "https://example.test/python-3.12-embed-amd64.zip",
      "sha256": "…64 位十六进制…",
      "fileName": "python-embed.zip",
      "license": "PSF-2.0",
      "licenseUrl": "https://example.test/python/LICENSE.txt",
      "archive": true,
      "extractTo": "python"
    },
    {
      "name": "VapourSynth R81",
      "url": "https://example.test/VapourSynth-R81.zip",
      "sha256": "…",
      "fileName": "vapoursynth.zip",
      "license": "LGPL-2.1",
      "archive": true,
      "extractTo": "python/Lib/site-packages",
      "stripComponents": 1
    },
    {
      "name": "mvtools",
      "url": "https://example.test/mvtools.zip",
      "sha256": "…",
      "fileName": "mvtools.zip",
      "license": "GPL-2.0",
      "archive": true,
      "extractTo": "python/Lib/site-packages/vapoursynth/plugins",
      "stripComponents": 1
    },
    {
      "name": "librife（VapourSynth-RIFE-ncnn-Vulkan）",
      "url": "https://example.test/librife.dll",
      "sha256": "…",
      "fileName": "librife.dll",
      "license": "MIT",
      "target": "python/Lib/site-packages/vapoursynth/plugins/librife.dll"
    },
    {
      "name": "RIFE v4.6 模型",
      "url": "https://example.test/rife-v4.6.zip",
      "sha256": "…",
      "fileName": "rife-v4.6.zip",
      "license": "MIT",
      "archive": true,
      "extractTo": "python/Lib/site-packages/vapoursynth/plugins/models"
    }
  ]
}
```

字段：

| 字段 | 必填 | 说明 |
|---|---|---|
| `version` / `name` | ✓ / – | 版本号和显示名 |
| `files[]` | ✓ | 至少一项 |
| `name` | ✓ | 组件显示名 |
| `url` | ✓ | 只接受 `http://` / `https://` |
| `sha256` | ✓ | 64 位十六进制；下载后逐字节校验，失败即中止 |
| `fileName` | ✓ | 下载时的临时文件名 |
| `license` | ✓ | 许可证标识；为空会被拒绝，确认弹窗会逐项显示 |
| `licenseUrl` | – | 许可证原文地址 |
| `archive` | – | `true` 表示 zip，需要配合 `extractTo` |
| `extractTo` | archive 时 ✓ | 相对增强包目录的解压目标 |
| `stripComponents` | – | 解压时去掉前 N 层目录（发布包常带一层版本号目录） |
| `target` | – | 非压缩文件的相对落盘路径，默认 `fileName` |

安装器的安全约束：只接受 http(s)；`target`/`extractTo` 不能是绝对路径，也不能用 `..`
越出增强包目录；zip 内的条目同样检查，越界直接报错；临时文件放在 `.downloads/`，
安装结束（成功或失败）都会清理。

## 路径自动发现

安装完成后：

- Python 目录 = 第一个文件名匹配 `python3\d+.dll` 的 DLL 所在目录；
- VapourSynth 目录 = 同时包含 `vsscript.dll` 和 `vapoursynth.pyd` 的目录。

两个都找到才会写入设置；只找到 libmpv 时会提示手动填写。Python 目录和
VapourSynth 目录会在应用启动时由 `VapourSynthRuntime` 写进进程环境（Win32 与
C 运行时两份），不需要改系统环境变量。

## 许可证核对

| 组件 | 许可证 | 能否由我们托管再分发 |
|---|---|---|
| mpv / libmpv | GPL-2.0-or-later | 可以，但必须提供对应源码（或官方源码获取方式）；优先链接官方构建 |
| 便携 Python | PSF-2.0 | 可以，保留 PSF 许可证即可 |
| VapourSynth | LGPL-2.1 | 可以，需保留许可证并提供库的源码/替换方式 |
| mvtools | GPL-2.0 | 可以，但同样有源码提供义务；优先链接官方 release |
| VapourSynth-RIFE-ncnn-Vulkan | MIT | 可以，保留版权与许可声明 |
| RIFE v4.6 模型 | MIT | 可以，保留版权与许可声明 |

结论：**仓库不托管这些二进制**。manifest 只写官方发布地址，用户安装时自行下载；
如果以后要自建镜像，必须按上表随附许可证和源码获取方式。安装器要求每个文件都写
`license`，并在下载前把清单展示给用户确认，就是为了避免“来源不明的一键包”。

## 测试覆盖

`test/enhance_pack_bundle_test.dart` 用 `MockClient` 和内存 zip 覆盖：

- 多文件 manifest 解析；缺许可证/坏哈希被拒绝；
- 下载 → SHA256 校验 → 解压 → 找到 Python / VapourSynth 路径；
- 校验失败不落盘、清理 `.downloads`；
- zip 路径穿越（`../`）被拒绝；
- `stripComponents` 去掉发布包外层目录；
- 从 URL 拉取 manifest。

真实的大文件包（数 GB 下载、真实 RIFE 模型）仍需在有网络的机器上手动跑一次，
这一步记录在 `docs/VERIFICATION.md` 的“未验证”里。
