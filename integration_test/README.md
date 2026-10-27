# 集成测试（M7-1）

这里用 Flutter 官方 `integration_test` 在真实的 Windows 应用进程里驱动界面，
覆盖首页打开文件、播放页增强菜单、设置页凭据、订阅导入、在线搜索和离线任务页。

## 运行

```powershell
flutter test integration_test -d windows
```

CI（`.github/workflows/ci.yml`）在 release 构建之后跑同一命令。测试进程会创建真实窗口；
在开发机上想不占用桌面，可参考 `tool/hidden_smoke.ps1` 的独立桌面方式启动命令，
或者直接交给 CI。

## 测试素材

`fixtures/pattern.mp4` 是 6 秒、320×240、24fps 的 SMPTE 色条，没有音轨、没有版权素材。
需要重新生成时：

```powershell
ffmpeg -y -f lavfi -i "smptebars=size=320x240:rate=24:duration=6" `
  -c:v libx264 -preset veryfast -crf 30 -pix_fmt yuv420p `
  integration_test/fixtures/pattern.mp4
```

测试通过向上查找 `pubspec.yaml` 定位项目根目录，所以从哪个工作目录启动都能找到素材。

## 隔离

- `SharedPreferences.setMockInitialValues({})` 在内存里重置设置，不读写用户真实的
  `%APPDATA%` 配置。
- 网络：在线搜索使用测试内注入的假 adapter；订阅导入使用粘贴 JSON，不访问网络。
- 播放使用仓库内的色条视频，允许真实媒体管线（media_kit/mpv）跑起来。
- 测试结束会卸载播放页，释放 libmpv；不启动安装包、不写桌面。
