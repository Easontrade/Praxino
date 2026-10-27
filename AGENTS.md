# Praxino 开发指南（给 AI 代理和贡献者）

开始之前先读这两份文档：

1. [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)：分层、接口、设计理由
2. [`docs/ROADMAP.md`](docs/ROADMAP.md)：按顺序排好的任务卡，每张卡都写了验收标准

## 工作方式

- 一次只做**一张任务卡**。做之前把卡片重读一遍；做完逐条核对验收标准。
- 改了架构（新增层、新增接口、换依赖），就先更新 `docs/ARCHITECTURE.md`，再写代码。
- 完成后把 ROADMAP 里这张卡的 ⏳ 改成 ✅，和代码放在同一个提交里。
- 卡片里没写清楚、需要做取舍的地方，停下来问人，不要自己猜。

## 必须遵守的规则

1. **分层**：`lib/core/` 不能 import `material.dart`，也不能 import 任何 `lib/ui/` 下的文件。只有 `lib/core/player/` 可以调用 `setProperty`/`command`。
2. **mpv 配置写成纯函数**：参考 `EnhanceSettings.toMpvProperties`，先写单测，再接到播放器上。
3. **测试不访问网络**：HTTP 一律通过可注入的 `http.Client`，测试里用 `package:http/testing.dart` 的 `MockClient`。
4. **仓库里不放真实视频站点**：域名、规则、API Key 都不行，示例统一用 `example.test`。真实规则只放在仓库外的私有目录（见 `AGENTS.local.md`），用来手动测试。
5. **第三方资源**（着色器、模型、字体）要把它的 LICENSE 放在同一个目录里。
6. **不要添加**会执行远程代码的源类型（TVBox 的 JAR/Python 爬虫等）。
7. 跟随周围代码的风格：注释密度、命名、写法。用户可见的文本写中文，代码注释和标识符写英文。
8. **不要打扰用户的桌面**：不要主动启动会弹窗、抢焦点或播放声音的程序（包括 `praxino.exe` 和
   `flutter run`）。`flutter analyze`、`flutter test`、`flutter build` 可以跑；需要肉眼验证 UI 时，
   先问用户，或把命令交给用户自己执行并把结果告诉你。也不要把构建产物、日志或临时文件写到桌面，
   一律放在项目目录或系统临时目录。
9. **不复制外部项目代码**：Kazumi 等项目的代码/补丁只用于行为对照，不复制、不移植；
   Kazumi 规则只作为可选的输入格式。算法和数据结构按本项目文档自己设计。

## 命令

需要 Flutter 3.47 和 Git。本机特定的设置（PATH、测试素材、私有对照资料）写在仓库根目录的
`AGENTS.local.md` 里：它不提交到 Git，存在就先读它，不存在就跳过。

| 用途 | 命令 |
|---|---|
| 静态检查（必须 0 issue） | `flutter analyze` |
| 单元测试（必须全过） | `flutter test` |
| 构建 | `flutter build windows --debug` |
| 发布构建（CI 用） | `flutter build windows --release` |
| 运行并带一个文件（**由用户执行**，代理不要自己跑） | `flutter run -d windows --dart-entrypoint-args "D:\path\to\video.mkv"` |

调试日志：debug 构建会把 mpv 的 warn 级别以上日志打印成 `[mpv:...]`，
画质设置变化时会打印 `[enhance] {...} shaders=...`，可以用它确认着色器是否真的加载了。
无窗口运行（隐藏桌面，没有控制台）时，设置环境变量 `PRAXINO_DIAG_LOG=<文件>`，debug 构建会把 mpv 日志
和每 2 秒一次的 `[stats] height/fps/dropped/vf` 追加到这个文件里，用来验证补帧等效果。

## 提交

- 使用 Conventional Commits：`feat(player): …`、`fix(sources): …`、`docs: …`、`test: …`、`chore: …`
- 一张任务卡对应一个或少量几个提交；不要把无关的格式化改动混进来。
- 推送前确认 `flutter analyze` 和 `flutter test` 都通过（推送到 GitHub 后 CI 会再检查一遍）。

## 手动验证

UI 相关的卡需要实际验证，但**不要由代理在用户桌面上直接启动播放器**（会弹窗、抢焦点、出声）。
优先用 `flutter test` 和 widget test 验证逻辑；需要看真实画面时，把命令交给用户执行，等用户反馈。
本机测试素材见 `AGENTS.local.md`。
无法自动验证的地方（比如快捷键、画面观感），在提交说明里写清楚"未手动验证"，不要声称已经验证过。
