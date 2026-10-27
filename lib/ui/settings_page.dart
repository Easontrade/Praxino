import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/enhance/enhance_pack.dart';
import '../core/enhance/enhance_pack_activation.dart';
import '../core/enhance/enhance_pack_paths.dart';
import '../core/settings/keybindings.dart';
import '../core/settings/settings_store.dart';
import '../core/subtitles/opensubtitles_provider.dart';
import '../core/update/update_checker.dart';
import 'jellyfin_servers_page.dart';
import 'key_chord_ui.dart';
import 'offline_tasks_page.dart';
import 'webdav_servers_page.dart';

/// App settings. Today this is the keybinding editor; paths and credentials
/// will live here as the related cards land.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings});

  final SettingsStore settings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Keybindings _keys;

  @override
  void initState() {
    super.initState();
    _keys = widget.settings.keybindings;
  }

  Future<void> _record(PlayerAction action) async {
    final chord = await showDialog<KeyChord>(
      context: context,
      builder: (_) => _ShortcutDialog(initial: _keys.chordFor(action)),
    );
    if (chord == null || !mounted) return;
    try {
      _keys.assign(action, chord);
    } on ArgumentError {
      _toast('这个组合已经被另一个动作使用');
      return;
    }
    setState(() {});
    await widget.settings.saveKeybindings(_keys);
  }

  Future<void> _reset(PlayerAction action) async {
    setState(() => _keys.reset(action));
    await widget.settings.saveKeybindings(_keys);
  }

  Future<void> _resetAll() async {
    setState(_keys.resetAll);
    await widget.settings.saveKeybindings(_keys);
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openSubtitles() async {
    final apiKey = TextEditingController(
      text: widget.settings.openSubtitlesApiKey,
    );
    final username = TextEditingController(
      text: widget.settings.openSubtitlesUsername,
    );
    final password = TextEditingController(
      text: widget.settings.openSubtitlesPassword,
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('OpenSubtitles'),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: apiKey,
                decoration: const InputDecoration(labelText: 'API Key'),
              ),
              TextField(
                controller: username,
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密码'),
              ),
              const SizedBox(height: 8),
              const Text('登录后下载额度约每天 20 次；不登录仍可匿名搜索。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('登录并保存'),
          ),
        ],
      ),
    );
    if (saved == true) {
      final provider = OpenSubtitlesProvider(
        apiKey: apiKey.text.trim(),
        appVersion:
            const String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0'),
      );
      try {
        final login = await provider.login(
          username: username.text.trim(),
          password: password.text,
        );
        await widget.settings.setOpenSubtitlesCredentials(
          apiKey: apiKey.text.trim(),
          username: username.text.trim(),
          password: password.text,
          token: login.token,
        );
        if (mounted) {
          _toast(login.remainingDownloads == null
              ? 'OpenSubtitles 登录成功'
              : 'OpenSubtitles 登录成功，剩余下载 ${login.remainingDownloads} 次');
          setState(() {});
        }
      } on Exception catch (error) {
        if (mounted) _toast('$error');
      } finally {
        provider.close();
      }
    }
    apiKey.dispose();
    username.dispose();
    password.dispose();
  }

  Future<void> _dandanplayCredentials() async {
    final appId = TextEditingController(
      text: widget.settings.dandanplayAppId,
    );
    final secret = TextEditingController(
      text: widget.settings.dandanplayAppSecret,
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('弹弹play 凭证'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: appId,
                decoration: const InputDecoration(labelText: 'AppId'),
              ),
              TextField(
                controller: secret,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'AppSecret'),
              ),
              const SizedBox(height: 8),
              const Text(
                '也支持环境变量 PRAXINO_DANDAN_APP_ID / '
                'PRAXINO_DANDAN_APP_SECRET。',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await widget.settings.setDandanplayCredentials(
        appId.text.trim(),
        secret.text.trim(),
      );
      if (mounted) setState(() {});
    }
    appId.dispose();
    secret.dispose();
  }

  Future<void> _vpyScript() async {
    final path = TextEditingController(
      text: widget.settings.interpolationScriptPath ?? '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('补帧脚本'),
        content: SizedBox(
          width: 620,
          child: TextField(
            controller: path,
            decoration: const InputDecoration(
              labelText: '自定义 .vpy 路径（留空使用内置模板）',
              hintText: r'C:\Tools\vs\my_interp.vpy',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await widget.settings.setInterpolationScriptPath(path.text);
      if (mounted) setState(() {});
    }
    path.dispose();
  }

  Future<void> _enhancePack() async {
    final manifest = TextEditingController();
    final installed = EnhancePackPaths.installed();
    final activation = EnhancePackActivation();
    final python =
        TextEditingController(text: widget.settings.vapoursynthRuntime.pythonDir);
    final site =
        TextEditingController(text: widget.settings.vapoursynthRuntime.siteDir);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('增强包 / 补帧'),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(installed
                  ? '已下载：${EnhancePackPaths.libmpv()}\n'
                      '${activation.isActive ? '已启用（替换了应用自带的 libmpv）' : '未启用'}'
                  : '未安装。下载带 VapourSynth 的 libmpv 后启用，重启应用生效。'),
              const SizedBox(height: 12),
              TextField(
                controller: python,
                decoration: const InputDecoration(
                  labelText: 'Python 目录（含 python3xx.dll）',
                  hintText: r'C:\Tools\python',
                ),
              ),
              TextField(
                controller: site,
                decoration: const InputDecoration(
                  labelText: 'VapourSynth 目录（site-packages\\vapoursynth）',
                  hintText: r'C:\Tools\python\Lib\site-packages\vapoursynth',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: manifest,
                minLines: 5,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'manifest JSON',
                  hintText:
                      '{"version":"1","url":"https://…/libmpv-2.dll","sha256":"…"}',
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (installed)
            TextButton(
              onPressed: () => Navigator.pop(context, 'remove'),
              child: const Text('移除'),
            ),
          if (installed)
            TextButton(
              onPressed: () => Navigator.pop(
                  context, activation.isActive ? 'deactivate' : 'activate'),
              child: Text(activation.isActive ? '停用' : '启用'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, manifest.text.trim()),
            child: const Text('保存 / 下载并启用'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) {
      manifest.dispose();
      python.dispose();
      site.dispose();
      return;
    }
    await widget.settings
        .setVapoursynthRuntime(pythonDir: python.text, siteDir: site.text);
    python.dispose();
    site.dispose();
    if (!mounted) {
      manifest.dispose();
      return;
    }

    try {
      switch (result) {
        case 'remove':
          activation.deactivate();
          final file = File(EnhancePackPaths.libmpv());
          if (await file.exists()) await file.delete();
          _toast('已移除增强包，重启 Praxino 后恢复自带的 libmpv');
        case 'deactivate':
          activation.deactivate();
          _toast('已停用，重启 Praxino 后生效');
        case 'activate':
          _activatePack(activation);
        case '':
          _toast('已保存 VapourSynth 路径，重启后生效');
        default:
          final parsed = EnhancePackManifest.tryFromJson(jsonDecode(result));
          if (parsed == null) throw const EnhancePackException('manifest 格式不对');
          final downloader = EnhancePackDownloader(root: EnhancePackPaths.root());
          try {
            await downloader.download(parsed);
          } finally {
            downloader.close();
          }
          _activatePack(activation);
      }
    } on Exception catch (error) {
      if (mounted) _toast('$error');
    } finally {
      manifest.dispose();
      if (mounted) setState(() {});
    }
  }

  void _activatePack(EnhancePackActivation activation) {
    if (!EnhancePackPaths.compatible()) {
      throw const EnhancePackException('这个 libmpv 的 client API 低于 2.1，不能启用');
    }
    activation.activate(EnhancePackPaths.libmpv());
    _toast('增强包已启用，重启 Praxino 后生效');
  }

  String _toolSummary() {
    final count = [
      widget.settings.offlineFfmpegPath,
      widget.settings.offlineEsrganPath,
      widget.settings.offlineRifePath,
    ].where((path) => path != null && path.isNotEmpty).length;
    return count == 0 ? '未配置，将退回 ffmpeg 重编码' : '已配置 $count 个工具';
  }

  Future<void> _offlineTools() async {
    final ffmpeg = TextEditingController(
      text: widget.settings.offlineFfmpegPath ?? '',
    );
    final esrgan = TextEditingController(
      text: widget.settings.offlineEsrganPath ?? '',
    );
    final rife = TextEditingController(
      text: widget.settings.offlineRifePath ?? '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('离线增强工具路径'),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ffmpeg,
                decoration: const InputDecoration(
                  labelText: 'ffmpeg.exe',
                  hintText: r'C:\Tools\ffmpeg\bin\ffmpeg.exe',
                ),
              ),
              TextField(
                controller: esrgan,
                decoration: const InputDecoration(
                  labelText: 'realesrgan-ncnn-vulkan.exe',
                ),
              ),
              TextField(
                controller: rife,
                decoration: const InputDecoration(
                  labelText: 'rife-ncnn-vulkan.exe',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await widget.settings.setOfflineToolPaths(
        ffmpeg: ffmpeg.text,
        esrgan: esrgan.text,
        rife: rife.text,
      );
    }
    ffmpeg.dispose();
    esrgan.dispose();
    rife.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _checkUpdates() async {    final checker = UpdateChecker(
      currentVersion:
          const String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0'),
      skippedVersion: widget.settings.skippedUpdateVersion,
    );
    final info = await checker.check();
    checker.close();
    if (!mounted) return;
    if (info == null) {
      _toast('已是最新版本，或暂时无法检查更新');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('发现新版本 ${info.version}'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(info.url),
              if (info.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(child: Text(info.notes)),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await widget.settings.setSkippedUpdateVersion(info.version);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('跳过此版本'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: info.url));
              Navigator.pop(context);
              _toast('下载地址已复制');
            },
            child: const Text('复制下载地址'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.hourglass_bottom),
            title: const Text('离线增强任务'),
            subtitle: const Text('后台超分/补帧队列'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => OfflineTasksPage(settings: widget.settings),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.system_update_alt),
            title: const Text('检查更新'),
            subtitle: const Text('从 GitHub Releases 检查新版本'),
            onTap: _checkUpdates,
          ),
          ListTile(
            leading: const Icon(Icons.build_outlined),
            title: const Text('离线增强工具路径'),
            subtitle: Text(
              _toolSummary(),
            ),
            onTap: _offlineTools,
          ),
          ListTile(
            leading: const Icon(Icons.memory),
            title: const Text('增强包 / 补帧'),
            subtitle: Text(
              !EnhancePackPaths.installed()
                  ? '未安装'
                  : EnhancePackActivation().isActive
                      ? '已启用 libmpv（VapourSynth）'
                      : '已下载，未启用',
            ),
            onTap: _enhancePack,
          ),
          ListTile(
            leading: const Icon(Icons.forum_outlined),
            title: const Text('弹弹play 凭证'),
            subtitle: Text(
              widget.settings.dandanplayAppId.isEmpty
                  ? '未配置（只影响本地弹幕匹配）'
                  : '已配置 AppId',
            ),
            onTap: _dandanplayCredentials,
          ),
          ListTile(
            leading: const Icon(Icons.closed_caption_outlined),
            title: const Text('OpenSubtitles'),
            subtitle: Text(
              widget.settings.openSubtitlesApiKey.isEmpty
                  ? '未配置 API Key'
                  : widget.settings.openSubtitlesToken.isEmpty
                      ? '已配置 API Key，未登录'
                      : '已登录',
            ),
            onTap: _openSubtitles,
          ),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('WebDAV / OpenList'),
            subtitle: Text(
              widget.settings.webdavServers.isEmpty
                  ? '未配置服务器'
                  : '已配置 ${widget.settings.webdavServers.length} 个服务器',
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => WebDavServersPage(settings: widget.settings),
            )),
          ),
          ListTile(
            leading: const Icon(Icons.video_library_outlined),
            title: const Text('Jellyfin / Emby'),
            subtitle: Text(
              widget.settings.jellyfinServers.isEmpty
                  ? '未配置服务器'
                  : '已配置 ${widget.settings.jellyfinServers.length} 个服务器',
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => JellyfinServersPage(settings: widget.settings),
            )),
          ),
          ListTile(
            leading: const Icon(Icons.movie_filter_outlined),
            title: const Text('补帧脚本'),
            subtitle: Text(
              widget.settings.interpolationScriptPath ?? '使用内置模板（mvtools / RIFE）',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: _vpyScript,
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('播放器快捷键', style: Theme.of(context).textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '点击右侧按钮重新录制；组合冲突时不会保存。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final action in PlayerAction.values)
            ListTile(
              title: Text(_actionLabels[action]!),
              subtitle: Text(_keys.chordFor(action)?.label ?? '未设置'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '修改',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _record(action),
                  ),
                  IconButton(
                    tooltip: '恢复默认',
                    icon: const Icon(Icons.restore),
                    onPressed: () => _reset(action),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.tonal(
              onPressed: _resetAll,
              child: const Text('全部恢复默认'),
            ),
          ),
        ],
      ),
    );
  }
}

const Map<PlayerAction, String> _actionLabels = {
  PlayerAction.upscaleOff: '超分辨率：关闭',
  PlayerAction.upscaleFast: '超分辨率：流畅',
  PlayerAction.upscaleBalanced: '超分辨率：均衡',
  PlayerAction.upscaleQuality: '超分辨率：高质量',
  PlayerAction.toggleEnhance: '画质修复开关',
  PlayerAction.subtitleDelayDown: '字幕延迟 −0.1s',
  PlayerAction.subtitleDelayUp: '字幕延迟 +0.1s',
  PlayerAction.speedDown: '播放速度 −0.1x',
  PlayerAction.speedUp: '播放速度 +0.1x',
  PlayerAction.screenshot: '截图',
  PlayerAction.togglePlaylist: '播放列表',
};

/// Records one chord; modifier-only presses are ignored.
class _ShortcutDialog extends StatefulWidget {
  const _ShortcutDialog({this.initial});

  final KeyChord? initial;

  @override
  State<_ShortcutDialog> createState() => _ShortcutDialogState();
}

class _ShortcutDialogState extends State<_ShortcutDialog> {
  late KeyChord? _chord = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('按下新快捷键'),
      content: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          final chord = chordForEvent(event);
          if (chord == null) return KeyEventResult.ignored;
          setState(() => _chord = chord);
          return KeyEventResult.handled;
        },
        child: Text(
          _chord?.label ?? '等待按键…',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _chord == null
              ? null
              : () => Navigator.pop(context, _chord),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
