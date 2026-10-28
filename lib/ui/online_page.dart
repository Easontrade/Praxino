import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/settings/settings_store.dart';
import '../core/sources/browser/webview_browser_fetch.dart';
import '../core/sources/extra_source.dart';
import '../core/sources/reliability/title_match.dart';
import '../core/sources/script/script_adapter.dart';
import '../core/sources/source_adapter.dart';
import '../core/sources/source_registry.dart';
import '../core/sources/source_report.dart';
import '../core/sources/source_report_runner.dart';
import '../core/sources/stremio/stremio_adapter.dart';
import '../core/sources/tvbox/tvbox_adapter.dart';
import '../core/sources/tvbox/tvbox_config.dart';
import '../core/sources/ytdlp/ytdlp_adapter.dart';
import 'extra_sources_page.dart';
import 'media_detail_page.dart';
import 'source_report_page.dart';
import 'source_report_play.dart';
import 'subscriptions_page.dart';
import 'webview_browser_host.dart';

/// Searches every enabled subscription and drills into one hit.
///
/// The page owns no sources; adapters come from the user's subscriptions.
class OnlinePage extends StatefulWidget {
  const OnlinePage({super.key, required this.settings, this.adapters});

  final SettingsStore settings;

  /// Test seam: when provided, subscriptions are not read or fetched.
  final List<SourceAdapter>? adapters;

  @override
  State<OnlinePage> createState() => _OnlinePageState();
}

class _OnlinePageState extends State<OnlinePage> {
  final TextEditingController _query = TextEditingController();
  final List<SourceSearchResult> _results = [];
  http.Client? _client;
  List<SourceAdapter> _adapters = const [];
  Map<String, SourceAdapter> _byId = const {};
  bool _searching = false;
  final Set<String> _unresponsive = {};
  late final WebViewBrowserFetch _browser;
  SourceReportRunner? _rankRunner;
  List<SourceReportEntry> _rankEntries = const [];
  int _rankDone = 0;
  int _rankTotal = 0;
  bool _rankRunning = false;

  @override
  void initState() {
    super.initState();
    _browser = WebViewBrowserFetch();
    unawaited(_rebuildAdapters());
  }

  @override
  void dispose() {
    _rankRunner?.close();
    unawaited(_browser.dispose());
    _client?.close();
    _query.dispose();
    super.dispose();
  }

  Future<void> _rebuildAdapters() async {
    if (widget.adapters != null) {
      _adapters = widget.adapters!;
      _byId = {for (final adapter in _adapters) adapter.id: adapter};
      return;
    }
    _client?.close();
    final client = http.Client();
    _client = client;
    final adapters = <SourceAdapter>[
      for (final subscription in widget.settings.subscriptions)
        if (subscription.enabled) ...subscription.toAdapters(client: client),
    ];
    _unresponsive.clear();
    if (await YtDlpAdapter.isAvailable()) {
      adapters.add(YtDlpAdapter());
    }
    for (final extra in widget.settings.extraSources.where((e) => e.enabled)) {
      try {
        switch (extra.type) {
          case ExtraSourceType.stremio:
            adapters.add(
              await StremioAdapter.load(extra.location, client: client),
            );
          case ExtraSourceType.script:
            adapters.add(
              ScriptAdapter(
                id: 'script:${extra.id}',
                name: extra.name,
                script: extra.location,
              ),
            );
        }
      } catch (_) {
        // One broken addon/script must not hide the other sources.
      }
    }
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      final sites = await TvBoxConfigLoader.loadDirectory(
        Directory(p.join(appData, 'Praxino', 'tvbox')),
      );
      for (final site in sites.where((site) => site.searchable)) {
        adapters.add(
          TvBoxAdapter(
            api: site.api,
            displayName: site.name,
            browser: _browser,
            client: client,
          ),
        );
      }
    }
    if (!mounted) {
      client.close();
      return;
    }
    setState(() {
      _adapters = adapters;
      _byId = {for (final adapter in adapters) adapter.id: adapter};
    });
  }

  Future<void> _openSubscriptions() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubscriptionsPage(settings: widget.settings),
      ),
    );
    if (!mounted) return;
    await _rebuildAdapters();
  }

  Future<void> _openExtraSources() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExtraSourcesPage(settings: widget.settings),
      ),
    );
    if (!mounted) return;
    await _rebuildAdapters();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    if (_adapters.isEmpty) {
      _toast('还没有启用的订阅源，先在右上角添加订阅');
      return;
    }
    _rankRunner?.close();
    setState(() {
      _searching = true;
      _results.clear();
      _rankEntries = const [];
      _rankDone = 0;
      _rankTotal = 0;
      _rankRunning = false;
    });
    final registry = SourceRegistry(
      timeout: const Duration(seconds: 20),
      sources: [
        for (final adapter in _adapters)
          if (!_unresponsive.contains(adapter.id)) adapter,
      ],
    );
    await for (final result in registry.search(query)) {
      if (!mounted) return;
      if (result.hasError) _unresponsive.add(result.sourceId);
      final items = [...result.items]
        ..sort(
          (a, b) => TitleMatcher.score(
            query,
            b.title,
          ).score.compareTo(TitleMatcher.score(query, a.title).score),
        );
      setState(
        () => _results.add(
          SourceSearchResult(
            sourceId: result.sourceId,
            sourceName: result.sourceName,
            items: items,
            error: result.error,
          ),
        ),
      );
    }
    if (!mounted) return;
    setState(() => _searching = false);
    _startRanking(_reportInputs());
  }

  bool _relevant(String query, String title) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (title.toLowerCase().contains(q)) return true;
    final normalizedTitle = TitleMatcher.normalizeTitle(title);
    final normalizedQuery = TitleMatcher.normalizeTitle(query);
    if (normalizedQuery.isNotEmpty &&
        normalizedTitle.contains(normalizedQuery)) {
      return true;
    }
    return TitleMatcher.score(query, title).score >= 0.45;
  }

  List<SourceReportInput> _reportInputs() {
    final query = _query.text.trim();
    return [
      for (final result in _results)
        if (_byId[result.sourceId] != null &&
            result.items.any((item) => _relevant(query, item.title)))
          SourceReportInput(
            adapter: _byId[result.sourceId]!,
            items: [
              for (final item in result.items)
                if (_relevant(query, item.title)) item,
            ],
          ),
    ];
  }

  void _startRanking(List<SourceReportInput> inputs) {
    _rankRunner?.close();
    if (inputs.isEmpty) {
      setState(() {
        _rankEntries = const [];
        _rankDone = 0;
        _rankTotal = 0;
        _rankRunning = false;
      });
      return;
    }
    final total = inputs.fold(0, (sum, input) => sum + input.items.length);
    final runner = SourceReportRunner(
      query: _query.text.trim(),
      inputs: inputs,
    );
    _rankRunner = runner;
    setState(() {
      _rankEntries = const [];
      _rankDone = 0;
      _rankTotal = total;
      _rankRunning = true;
    });
    unawaited(
      runner.run(
        onUpdate: () {
          if (!mounted || _rankRunner != runner) return;
          setState(() {
            _rankEntries = List.of(runner.entries);
            _rankDone = runner.done;
            _rankRunning = runner.running;
          });
        },
      ),
    );
  }

  Future<void> _copy(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    _toast('链接已复制');
  }

  Future<void> _open(SourceSearchResult result, MediaSummary media) async {
    final adapter = _byId[result.sourceId];
    if (adapter == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaDetailPage(
          adapter: adapter,
          media: media,
          settings: widget.settings,
        ),
      ),
    );
  }

  Future<void> _openSourceReport() async {
    final inputs = <SourceReportInput>[];
    for (final result in _results) {
      final adapter = _byId[result.sourceId];
      if (adapter == null || result.items.isEmpty) continue;
      inputs.add(SourceReportInput(adapter: adapter, items: result.items));
    }
    if (inputs.isEmpty) {
      _toast('先搜索，有结果后才能生成源排行');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SourceReportPage(
          query: _query.text.trim(),
          inputs: inputs,
          settings: widget.settings,
        ),
      ),
    );
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return WebViewBrowserHost(
      controller: _browser.controller,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('在线搜索'),
          actions: [
            IconButton(
              tooltip: '完整源排行',
              icon: const Icon(Icons.leaderboard_outlined),
              onPressed: _results.isEmpty ? null : _openSourceReport,
            ),
            IconButton(
              tooltip: '扩展源',
              icon: const Icon(Icons.extension),
              onPressed: _openExtraSources,
            ),
            IconButton(
              tooltip: '管理订阅',
              icon: const Icon(Icons.rss_feed),
              onPressed: _openSubscriptions,
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _query,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '输入片名，回车搜索',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: '搜索',
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _searching ? null : _search,
                  ),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            if (_searching) const LinearProgressIndicator(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_adapters.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('还没有启用的订阅源。', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _openSubscriptions,
                icon: const Icon(Icons.add),
                label: const Text('添加订阅'),
              ),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return const Center(child: Text('搜索后，结果会按源分组显示在这里。'));
    }
    final okCount = _results
        .where((result) => !result.hasError && result.items.isNotEmpty)
        .length;
    final failedCount = _results.where((result) => result.hasError).length;
    return ListView(
      children: [
        if (_results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '$okCount 个源有结果 · $failedCount 个源未响应',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (_rankRunning || _rankEntries.isNotEmpty) _rankingSection(),
        if (_rankEntries.isNotEmpty) const Divider(thickness: 2),
        for (final result in _results.where((result) => !result.hasError)) ...[
          ListTile(
            title: Text(result.sourceName),
            subtitle: Text('${result.items.length} 个结果'),
          ),
          if (result.items.isEmpty)
            const ListTile(title: Text('没有结果'))
          else
            for (final media in result.items)
              ListTile(
                leading: const Icon(Icons.movie_outlined),
                title: Text(media.title),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(result, media),
              ),
          const Divider(),
        ],
        if (failedCount > 0)
          ExpansionTile(
            leading: const Icon(Icons.cloud_off_outlined),
            title: Text('其他源未响应（$failedCount）'),
            subtitle: const Text('多为失效的公开 TVBox 配置或网络超时，不影响上方可用源'),
            children: [
              for (final result in _results.where((result) => result.hasError))
                ListTile(
                  dense: true,
                  title: Text(result.sourceName),
                  subtitle: Text('${result.error}'),
                ),
            ],
          ),
      ],
    );
  }

  Widget _rankingSection() {
    final progress = _rankTotal == 0 ? null : _rankDone / _rankTotal;
    final watchable = [
      for (final entry in _rankEntries)
        if (entry.watchable) entry,
    ];
    final broken = [
      for (final entry in _rankEntries)
        if (!entry.watchable) entry,
    ];
    final best = SourceReport.bestEntry(watchable);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.leaderboard_outlined),
          title: const Text('源排行（自动检测）'),
          subtitle: Text(
            _rankRunning
                ? '正在检测 $_rankDone / $_rankTotal 个源'
                : '能看 ${watchable.length} 个 · 打不开 ${broken.length} 个',
          ),
          trailing: _rankRunning
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  tooltip: '重新检测',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _startRanking(_reportInputs()),
                ),
        ),
        if (_rankRunning) LinearProgressIndicator(value: progress),
        if (best != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: FilledButton.icon(
              onPressed: () => playReportEntry(context, widget.settings, best),
              icon: const Icon(Icons.play_arrow),
              label: Text(
                '播放最佳源：${best.sourceName}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        for (final entry in watchable) _rankRow(entry),
        if (broken.isNotEmpty)
          ExpansionTile(
            leading: const Icon(Icons.block, color: Colors.red),
            title: Text('打不开的源（${broken.length}）'),
            subtitle: const Text('检测时连不上，换一个能看的即可'),
            children: [for (final entry in broken) _rankRow(entry)],
          ),
      ],
    );
  }

  Widget _rankRow(SourceReportEntry entry) => ListTile(
    dense: true,
    leading: Icon(
      entry.watchable ? Icons.play_circle_outline : Icons.block,
      color: entry.watchable ? Colors.green : Colors.red,
    ),
    title: Text('${entry.sourceName} · ${entry.title}'),
    subtitle: Text(
      entry.quality == '未知' || entry.quality.isEmpty
          ? entry.verdict
          : '${entry.verdict} · ${entry.quality}',
      style: TextStyle(color: entry.watchable ? Colors.green : Colors.red),
    ),
    trailing: IconButton(
      tooltip: '复制链接',
      icon: const Icon(Icons.copy),
      onPressed: () => _copy(entry.link),
    ),
    onTap: entry.watchable
        ? () => playReportEntry(context, widget.settings, entry)
        : null,
  );
}
