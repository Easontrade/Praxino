# 验证记录

本文件记录本地 Windows 验证的状态。它只描述已经实际执行过的检查；没有执行的项目明确标为未验证。

## 自动检查

| 检查 | 结果 |
| --- | --- |
| `flutter analyze` | 0 issue |
| `flutter test` | 203 通过，6 个 QuickJS 测试在缺少插件 DLL 时跳过；指定 Release DLL 后 278 全通过 |
| `flutter build windows --debug` | 成功 |
| `flutter build windows --release` | 成功 |
| `flutter test integration_test -d windows` | 本地隐藏桌面 7/7 通过（打开文件、增强预设、增强弹窗在控制栏隐藏后仍可用、设置凭据、订阅导入、在线搜索、离线任务） |
| GitHub Actions CI | 待推送验证；本地带 QuickJS DLL 跑 278 个单元/Widget 测试 + 7 个集成测试，全通过 |
| Inno Setup 安装包编译 | 成功（包含降噪黑屏修复）；最终 SHA256 `7748a53c87af35630cc5534b1ac90be66146e33ed4e29a8612596076e1ee9adc` |
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
| WebDAV / OpenList | 已验证（Mock） | PROPFIND、中文/空格路径、401、同目录播放列表、Basic 认证头 |
| WebDAV 续播 / 下一集 / 同目录字幕 | 已验证（Mock） | 续播 key 去掉凭据和查询串（单测）；同目录视频按自然顺序进播放列表，下一集走 mpv 原生列表；字幕按 `<视频>.<语言>.ass` 匹配并中文优先；真实 OpenList 未验证 |
| 增强包一键安装 | 已验证（Mock） | 多文件 manifest、SHA256、zip 解压、`..` 路径拒绝、Python/VapourSynth 路径自动发现；真实大文件包未下载验证 |
| 界面集成测试 | 已验证（本地隐藏桌面） | `integration_test/app_test.dart` 7/7：首页打开文件、增强菜单持久化、增强弹窗在控制栏隐藏后仍保持打开并可切换、设置页凭据、订阅 JSON 导入、注入源搜索选集、离线任务暂停；CI 待推送验证 |
| 增强弹窗抗控制栏自动隐藏 | 已验证（集成测试，真实鼠标事件） | 打开弹窗后把鼠标移到弹窗上并等待 4 秒（超过控制栏 3 秒隐藏时间），弹窗仍在，并从弹窗成功切换到 Anime4K 均衡 |
| AI 双语字幕管线 | 已验证（Mock） | Whisper JSON 解析、DeepSeek 对齐/重试/回退、术语表、40 句分批、ASS/SRT 生成、缓存命中不重复计费、费用确认、Key 缺失提示；真实 Whisper/DeepSeek 未验证 |
| AI 字幕设置与任务类型 | 已验证（Widget/单测） | 设置页保存 Whisper/DeepSeek 配置；离线任务页区分超分与双语字幕、暂停排队任务；旧任务 JSON 无 `type` 时回退为超分 |
| 内置 libmpv 的降噪 | 已验证 | 内置 libmpv 没有 `hqdn3d`，旧的 `vf=lavfi` 会让视频输出失败并黑屏；改成 `denoise.glsl` GPU shader 后，在“Anime4K 高质量 + 去色带 + 降噪”的持久化设置下，1080p 23.976 正常播放（`[stats] height=1080 fps=23.976`，进度写入 watch history） |
| 源排行 | 已验证（Mock/Widget） | 搜索结果出来后自动逐源解析首集、探测直链、HLS 分辨率、质量/延迟/标题分排序、播放页识别、复制链接；顶部“播放最佳源”和每行播放按钮可一键进入播放，需抓流的源自动打开详情页并自动播放第一集；真实源检测用临时脚本跑过（30 个源命中 FX战士久留美，3 个直链可达） |
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








