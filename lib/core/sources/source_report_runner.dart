import 'dart:async';

import 'package:http/http.dart' as http;

import 'reliability/http_stream_prober.dart';
import 'reliability/source_prober.dart';
import 'reliability/title_match.dart';
import 'source_adapter.dart';
import 'source_report.dart';

/// Runs the source-ranking checks: resolve the first episode of every hit,
/// probe its stream and parse HLS resolution. Shared by the standalone report
/// page and the inline ranking on the search page.
class SourceReportRunner {
  SourceReportRunner({
    required this.query,
    required this.inputs,
    StreamProbe? probe,
    http.Client? httpClient,
    this.concurrency = 5,
  })  : _prober = probe == null ? HttpStreamProber() : null,
        _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null {
    _probe = probe ?? _prober!.probe;
  }

  final String query;
  final List<SourceReportInput> inputs;
  final int concurrency;
  final List<SourceReportEntry> entries = [];
  int total = 0;
  int done = 0;
  bool _cancelled = false;

  final HttpStreamProber? _prober;
  final http.Client _http;
  final bool _ownsClient;
  late final StreamProbe _probe;

  bool get running => done < total && !_cancelled;

  Future<void> run({void Function()? onUpdate}) async {
    _cancelled = false;
    entries.clear();
    done = 0;
    total = inputs.fold(0, (sum, input) => sum + input.items.length);
    if (total == 0) {
      onUpdate?.call();
      return;
    }
    final tasks = <Future<void> Function()>[];
    for (final input in inputs) {
      for (final media in input.items) {
        tasks.add(() => _check(input.adapter, media, onUpdate));
      }
    }
    var next = 0;
    Future<void> worker() async {
      while (true) {
        if (_cancelled) return;
        final index = next++;
        if (index >= tasks.length) return;
        await tasks[index]();
      }
    }

    await Future.wait(
      List.generate(tasks.length < concurrency ? tasks.length : concurrency,
          (_) => worker()),
    );
    onUpdate?.call();
  }

  void cancel() {
    _cancelled = true;
  }

  void close() {
    cancel();
    _prober?.close();
    if (_ownsClient) _http.close();
  }

  Future<void> _check(
    SourceAdapter adapter,
    MediaSummary media,
    void Function()? onUpdate,
  ) async {
    SourceReportEntry entry;
    final score = TitleMatcher.score(query, media.title).score;
    try {
      final groups = await adapter
          .episodes(media)
          .timeout(const Duration(seconds: 12));
      if (groups.isEmpty || groups.first.episodes.isEmpty) {
        entry = SourceReportEntry(
          sourceName: adapter.name,
          title: media.title,
          link: media.url,
          status: SourceReportStatus.unresolved,
          quality: '未知',
          matchScore: score,
          detail: '没有解析到剧集',
          adapter: adapter,
          media: media,
        );
      } else {
        final episode = groups.first.episodes.first;
        PlayableStream? stream;
        try {
          stream = await adapter
              .resolve(episode)
              .timeout(const Duration(seconds: 12));
        } catch (_) {
          stream = null;
        }
        if (stream == null ||
            SourceReport.looksLikeLandingPage(stream.url)) {
          final pageUrl = stream?.url ?? episode.url;
          // Most CMS play pages keep the real m3u8 in an inline script. Reading
          // it here turns "需抓流" into a row that plays on the first tap;
          // the WebView sniffer stays as the fallback.
          final extracted = await streamFromPage(pageUrl);
          final probe = extracted == null ? null : await _probe(extracted);
          if (extracted != null && probe != null && probe.reachable) {
            final hls = await hlsResolution(extracted);
            entry = SourceReportEntry(
              sourceName: adapter.name,
              title: media.title,
              link: extracted.url,
              status: SourceReportStatus.reachable,
              quality: SourceReport.qualityOf(
                height: extracted.height,
                width: extracted.width,
                title: '${media.title} ${episode.name}',
                url: extracted.url,
                hlsResolution: hls,
              ),
              matchScore: score,
              latency: probe.latency,
              stream: extracted,
              adapter: adapter,
              media: media,
              episode: episode,
            );
          } else {
            entry = SourceReportEntry(
              sourceName: adapter.name,
              title: media.title,
              link: pageUrl,
              status: SourceReportStatus.unresolved,
              quality: '未知',
              matchScore: score,
              detail: stream == null
                  ? '需要 WebView 抓流；从搜索结果打开这一集会继续解析'
                  : '这是播放页而不是直链，需要 WebView 抓流',
              stream: stream,
              adapter: adapter,
              media: media,
              episode: episode,
            );
          }
        } else {
          final hls = await hlsResolution(stream);
          final probe = await _probe(stream);
          final quality = SourceReport.qualityOf(
            height: stream.height,
            width: stream.width,
            title: '${media.title} ${episode.name}',
            url: stream.url,
            hlsResolution: hls,
          );
          entry = SourceReportEntry(
            sourceName: adapter.name,
            title: media.title,
            link: stream.url,
            status: probe.reachable
                ? SourceReportStatus.reachable
                : SourceReportStatus.unreachable,
            quality: quality,
            matchScore: score,
            latency: probe.latency,
            detail: probe.reachable ? '' : '${probe.error ?? '无法连接'}',
            stream: stream,
            adapter: adapter,
            media: media,
            episode: episode,
          );
        }
      }
    } catch (error) {
      entry = SourceReportEntry(
        sourceName: adapter.name,
        title: media.title,
        link: media.url,
        status: SourceReportStatus.unreachable,
        quality: '未知',
        matchScore: score,
        detail: '$error',
        adapter: adapter,
        media: media,
      );
    }
    if (_cancelled) return;
    entries.add(entry);
    done++;
    SourceReport.sort(entries);
    onUpdate?.call();
  }

  static const _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  /// Pulls a direct stream URL out of a player page's HTML.
  ///
  /// CMS sites usually embed it in an inline script, sometimes with escaped
  /// slashes; the Referer is the page's own origin, which is what almost every
  /// CDN asks for. Returns null when the page does not expose one.
  Future<PlayableStream?> streamFromPage(String pageUrl) async {
    final uri = Uri.tryParse(pageUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    final origin = '${uri.scheme}://${uri.host}/';
    final headers = {'User-Agent': _browserUserAgent, 'Referer': origin};
    try {
      final response =
          await _http.get(uri, headers: headers).timeout(const Duration(seconds: 6));
      if (response.statusCode >= 400) return null;
      final text = response.body.replaceAll(r'\/', '/');
      final match = RegExp(
        r'''https?://[^\s"'\\]+?\.(?:m3u8|mp4)[^\s"'\\]*''',
      ).firstMatch(text);
      if (match == null) return null;
      return PlayableStream(match.group(0)!, headers: headers);
    } catch (_) {
      return null;
    }
  }

  Future<String?> hlsResolution(PlayableStream stream) async {
    if (!stream.url.toLowerCase().contains('.m3u8')) return null;
    try {
      final response = await _http.get(
        Uri.parse(stream.url),
        headers: {...stream.headers, 'Range': 'bytes=0-131071'},
      ).timeout(const Duration(seconds: 6));
      if (response.statusCode >= 400) return null;
      final body = response.body;
      if (!body.contains('#EXTM3U')) return null;
      int? best;
      for (final match in RegExp(r'RESOLUTION=(\d+)x(\d+)').allMatches(body)) {
        final height = int.tryParse(match.group(2)!);
        if (height != null && (best == null || height > best)) best = height;
      }
      return best == null ? null : '0x$best';
    } catch (_) {
      return null;
    }
  }
}
