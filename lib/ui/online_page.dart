import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/settings/settings_store.dart';
import '../core/sources/extra_source.dart';
import '../core/sources/reliability/title_match.dart';
import '../core/sources/script/script_adapter.dart';
import '../core/sources/source_adapter.dart';
import '../core/sources/source_registry.dart';
import '../core/sources/source_report.dart';
import '../core/sources/stremio/stremio_adapter.dart';
import '../core/sources/tvbox/tvbox_adapter.dart';
import '../core/sources/tvbox/tvbox_config.dart';
import '../core/sources/ytdlp/ytdlp_adapter.dart';
import 'extra_sources_page.dart';
import 'media_detail_page.dart';
import 'source_report_page.dart';
import 'subscriptions_page.dart';

/// Searches every enabled subscription and drills into one hit.
///
/// The page owns no sources; adapters come from the user's subscriptions.
class OnlinePage extends StatefulWidget {
  const OnlinePage({
    super.key,
    required this.settings,
    this.adapters,
  });

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

  @override
  void initState() {
    super.initState();
    unawaited(_rebuildAdapters());
  }

  @override
  void dispose() {
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
      YtDlpAdapter(),
    ];
    for (final extra in widget.settings.extraSources.where((e) => e.enabled)) {
      try {
        switch (extra.type) {
          case ExtraSourceType.stremio:
            adapters.add(await StremioAdapter.load(
              extra.location,
              client: client,
            ));
          case ExtraSourceType.script:
            adapters.add(ScriptAdapter(
              id: 'script:${extra.id}',
              name: extra.name,
              script: extra.location,
            ));
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
        adapters.add(TvBoxAdapter(
          api: site.api,
          displayName: site.name,
          client: client,
        ));
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
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SubscriptionsPage(settings: widget.settings),
    ));
    if (!mounted) return;
    await _rebuildAdapters();
  }

  Future<void> _openExtraSources() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ExtraSourcesPage(settings: widget.settings),
    ));
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
    setState(() {
      _searching = true;
      _results.clear();
    });
    final registry = SourceRegistry(sources: _adapters);
    await for (final result in registry.search(query)) {
      if (!mounted) return;
      final items = [...result.items]..sort((a, b) => TitleMatcher.score(
            query,
            b.title,
          ).score.compareTo(TitleMatcher.score(query, a.title).score));
      setState(() => _results.add(SourceSearchResult(
            sourceId: result.sourceId,
            sourceName: result.sourceName,
            items: items,
            error: result.error,
          )));
    }
    if (mounted) setState(() => _searching = false);
  }

  Future<void> _open(SourceSearchResult result, MediaSummary media) async {
    final adapter = _byId[result.sourceId];
    if (adapter == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MediaDetailPage(
        adapter: adapter,
        media: media,
        settings: widget.settings,
      ),
    ));
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
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SourceReportPage(
        query: _query.text.trim(),
        inputs: inputs,
      ),
    ));
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('在线搜索'),
        actions: [
          IconButton(
            tooltip: '源排行',
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
    return ListView(
      children: [
        for (final result in _results) ...[
          ListTile(
            title: Text(result.sourceName),
            subtitle: Text(result.hasError
                ? '搜索失败'
                : '${result.items.length} 个结果'),
          ),
          if (result.hasError)
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text('${result.error}'),
            )
          else if (result.items.isEmpty)
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
      ],
    );
  }
}
