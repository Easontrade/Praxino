import 'dart:async';
import 'dart:convert';

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
    // Some CMS sites ignore the keyword and answer with their newest titles.
    // Probing those wastes requests and fills the list with unrelated shows.
    if (score < _minTitleScore) {
      done++;
      onUpdate?.call();
      return;
    }
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
        PlayableStream? resolved;
        try {
          resolved = await adapter
              .resolve(episode)
              .timeout(const Duration(seconds: 12));
        } catch (_) {
          resolved = null;
        }

        // Only a stream we verified may be labelled 能看. A direct URL is tried
        // first; when it is a play page (some sites even append /index.m3u8 to
        // one), the real URL is read out of the HTML and verified the same way.
        PlayableStream? playable;
        _Verified? verified;
        _Verified? directFailure;
        if (resolved != null && !SourceReport.looksLikeLandingPage(resolved.url)) {
          final direct = await _verify(resolved);
          if (direct.reachable) {
            playable = resolved;
            verified = direct;
          } else {
            directFailure = direct;
          }
        }
        if (playable == null) {
          for (final page
              in _pageCandidates(resolved?.url ?? episode.url)) {
            final extracted = await streamFromPage(page);
            if (extracted == null) continue;
            final check = await _verify(extracted);
            if (!check.reachable) continue;
            playable = extracted;
            verified = check;
            break;
          }
        }

        if (playable != null) {
          entry = SourceReportEntry(
            sourceName: adapter.name,
            title: media.title,
            link: playable.url,
            status: SourceReportStatus.reachable,
            quality: SourceReport.qualityOf(
              height: playable.height,
              width: playable.width,
              title: '${media.title} ${episode.name}',
              url: playable.url,
              hlsResolution: verified?.hls,
            ),
            matchScore: score,
            latency: verified?.latency,
            stream: playable,
            adapter: adapter,
            media: media,
            episode: episode,
          );
        } else if (directFailure != null) {
          entry = SourceReportEntry(
            sourceName: adapter.name,
            title: media.title,
            link: resolved!.url,
            status: SourceReportStatus.unreachable,
            quality: '未知',
            matchScore: score,
            latency: directFailure.latency,
            detail: directFailure.detail,
            stream: resolved,
            adapter: adapter,
            media: media,
            episode: episode,
          );
        } else {
          entry = SourceReportEntry(
            sourceName: adapter.name,
            title: media.title,
            link: resolved?.url ?? episode.url,
            status: SourceReportStatus.unresolved,
            quality: '未知',
            matchScore: score,
            detail: '没有找到能直接播放的地址',
            stream: resolved,
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
    // The same stream reached through four reseller sites is one playable row.
    final streamUrl = entry.stream?.url;
    final duplicate = streamUrl != null &&
        entries.any((existing) => existing.stream?.url == streamUrl);
    if (!duplicate) entries.add(entry);
    done++;
    SourceReport.sort(entries);
    onUpdate?.call();
  }

  /// Below this the search hit is not the title the user asked for.
  static const double _minTitleScore = 0.5;

  /// Proves the URL can actually start playback: the probe answers and, for
  /// HLS, the playlist parses. Finding a URL inside a play page is not enough
  /// to promise the user that tapping it will play.
  Future<_Verified> _verify(PlayableStream stream) async {
    final hls = await hlsResolution(stream);
    final playlistOk = await _playlistParses(stream);
    final probe = await _probe(stream);
    final reachable = probe.reachable && playlistOk;
    final detail = !probe.reachable
        ? '${probe.error ?? '无法连接'}'
        : !playlistOk
            ? '播放列表打不开'
            : '';
    return _Verified(
      reachable: reachable,
      latency: probe.latency,
      hls: hls,
      detail: detail,
    );
  }

  /// A URL plus, when the site appended `/index.m3u8` to a play page, the page
  /// itself: the manifest only exists once the page is opened in a browser.
  static List<String> _pageCandidates(String url) {
    final result = <String>[url];
    final lower = url.toLowerCase();
    if (!lower.endsWith('.m3u8') && !lower.endsWith('.mp4')) return result;
    final uri = Uri.tryParse(url);
    final slash = uri == null ? -1 : uri.path.lastIndexOf('/');
    if (uri == null || slash <= 0) return result;
    result.add(uri.replace(path: uri.path.substring(0, slash)).toString());
    return result;
  }

  /// A valid HLS playlist may carry no RESOLUTION at all, so this checks the
  /// manifest itself instead of reusing [hlsResolution].
  Future<bool> _playlistParses(PlayableStream stream) async {
    if (!stream.url.toLowerCase().contains('.m3u8')) return true;
    try {
      final response = await _http.get(
        Uri.parse(stream.url),
        headers: {...stream.headers, 'Range': 'bytes=0-131071'},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode >= 400) return false;
      return utf8
          .decode(response.bodyBytes, allowMalformed: true)
          .contains('#EXTM3U');
    } catch (_) {
      return false;
    }
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
          await _http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
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
      ).timeout(const Duration(seconds: 10));
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

/// Outcome of proving a stream can start.
class _Verified {
  const _Verified({
    required this.reachable,
    required this.hls,
    required this.detail,
    this.latency,
  });

  final bool reachable;
  final String? hls;
  final String detail;
  final Duration? latency;
}