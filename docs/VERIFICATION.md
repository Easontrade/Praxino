# 验证记录

本文件记录本地 Windows 验证的状态。它只描述已经实际执行过的检查；没有执行的项目明确标为未验证。

## 自动检查

| 检查 | 结果 |
| --- | --- |
| `flutter analyze` | 0 issue |
| `flutter test` | 192 通过，6 个 QuickJS 测试在缺少插件 DLL 时跳过；指定 Release DLL 后 198 全通过 |
| `flutter build windows --debug` | 成功 |
| `flutter build windows --release` | 成功 |
| GitHub Actions CI | 成功：build release 后带 QuickJS DLL 跑 198 个测试，无跳过 |
| Inno Setup 安装包编译 | 成功；最终 SHA256 `ed5ad5c4e128807d9f069a838e952e42e2ccf1baf5a321716c8b63c83e8e705d` |
| 安装包 ANGLE Vulkan 排除 | 已验证：安装目录无 `vulkan-1.dll` / `vk_swiftshader.dll` |

## 功能验证

| 项目 | 状态 | 证据 |
| --- | --- | --- |
| 本地视频播放 | 已验证 | 隐藏窗口播放测试视频，`watch_history` 记录进度 |
| 单实例 | 已验证 | 隐藏桌面启动两个进程，第二个退出，桌面仅一组窗口 |
| 安装/卸载 | 已验证 | 静默安装 → 启动 → 静默卸载；安装目录与 ProgID 清理 |
| 文件关联 | 已验证 | `.mp4` 安装后指向 `Praxino.Video`，卸载后恢复原值 |
| Kazumi 规则库 | 已验证 | 本地种子 16 条规则全部解析为 adapter |
| TVBox 本地配置 | 已验证 | 101 个去重地址导入成功 13 个；本地共 84 个可用站点 |
| 单源搜索 | 已验证 | 规则搜索返回结果（仅元数据，不播放） |
| Stremio adapter | 已验证（Mock） | manifest / catalog / meta / stream 解析 |
| QuickJS 沙箱 | 已验证 | 纯 JS、fetch、超时、内存上限、无文件/进程全局 |
| 弹幕布局性能 | 已验证 | 1000 条/分钟、600 帧平均低于 8ms/帧 |
| GPU 离线处理 | 已验证（1 分钟） | 1080p 60 秒 → 4K 48fps，862.8 秒，55,977,622 字节，音轨保留 |
| VapourSynth 运行时 | 已验证（独立） | `vspipe` 与 mpv `vapoursynth` filter 实际执行 `.vpy`；mvtools 30→60fps 脚本通过 |
| 在线字幕 | 已验证（Mock） | ASSRT / OpenSubtitles 搜索、下载、落盘；OpenSubtitles 登录、token 过期、额度用完 |
| 更新检查 | 已验证（Mock） | 新版本、同/旧版本、跳过、网络错误 |
| 隐藏桌面启动 | 已验证 | 独立桌面启动，窗口创建成功，不占用可见桌面 |
| 应用内 mvtools 补帧 | 已验证 | 增强包（shinchiro 2026 构建，client API 2.6）替换应用目录 libmpv；VapourSynth 路径来自设置；1080p 23.976 → 59.94 fps，`vf=vapoursynth` 生效，0 掉帧（`PRAXINO_DIAG_LOG` 每 2 秒采样，持续 12 秒以上） |
| 运行中启用增强包 | 已验证 | 应用运行时给已加载的 `libmpv-2.dll` 改名并放入新 DLL 成功；重启后加载新 DLL |
| 应用内 RIFE 补帧 | 已验证 | 内置 `rife_ncnn.vpy`（RIFE-ncnn-Vulkan + RIFE v4.6，RTX 5080）：1080p 23.976 → 47.952 fps，启动时掉 3 帧后 22 秒内不再增加 |
| RIFE 吞吐基准 | 已验证 | 独立 mpv `--untimed` 处理 10 秒 1080p：2 倍约 60fps；固定 60fps 约 37～41fps（GPU 100%），因此模板用 2 倍 |
| 去掉 ANGLE 附带的 Vulkan 文件后的普通播放 | 已验证 | 无增强包、Anime4K 高质量：1080p 23.976 fps 正常播放；mvtools 回归 59.94 fps |

## 未验证 / 外部条件

| 项目 | 原因 |
| --- | --- |
| 补帧肉眼观感 | 只验证了帧率和掉帧数，mvtools / RIFE 的画面需要用户亲自看 |
| 其它显卡上的 RIFE 实时性 | 只在 RTX 5080 上测过；较弱的显卡可能需要降到 mvtools |
| 真实 Stremio addon / 脚本源 | 没有可公开分发的测试 addon；仓库不内置真实源 |
| 真实在线字幕账号 | 没有 ASSRT/OpenSubtitles 凭证 |
| GitHub Release 自动发布 | 需要推送 tag；本地只验证了安装包与校验和 |
| 3 个真实源播放 / WebView 抓流 | 需要私有测试规则与实际站点；仓库不内置 |
| 隐藏桌面点击级 UI 自动化 | 当前隐藏桌面只做启动、窗口枚举、单实例 |

## 复现命令

```powershell
flutter analyze
flutter test
flutter build windows --debug
flutter build windows --release
```

QuickJS 测试需要先构建 Windows 插件 DLL：

```powershell
$env:FLUTTER_QJS_NEXT_LIBRARY = (Resolve-Path "build\windows\x64\runner\Release\flutter_qjs_next_plugin.dll")
flutter test
```
