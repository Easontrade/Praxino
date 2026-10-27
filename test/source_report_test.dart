import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxino/core/sources/reliability/source_prober.dart';
import 'package:praxino/core/sources/source_adapter.dart';
import 'package:praxino/core/sources/source_report.dart';
import 'package:praxino/ui/source_report_page.dart';

SourceReportEntry _entry(
  String source, {
  required SourceReportStatus status,
  String quality = '未知',
  Duration? latency,
  double score = 1,
}) =>
    SourceReportEntry(
      sourceName: source,
      title: 'FX战士久留美',
      link: 'https://example.test/$source',
      status: status,
      quality: quality,
      matchScore: score,
      latency: latency,
    );

void main() {
  test('quality comes from metadata, HLS resolution, title or URL', () {
    expect(SourceReport.qualityOf(height: 1080), '1080p');
    expect(SourceReport.qualityOf(hlsResolution: '0x2160'), '4K');
    expect(SourceReport.qualityOf(title: '某番 4K 收藏版'), '4K');
    expect(SourceReport.qualityOf(url: 'https://x/1080/index.m3u8'), '1080p');
    expect(SourceReport.qualityOf(title: '720P'), '720p');
    expect(SourceReport.qualityOf(), '未知');
    expect(SourceReport.qualityRank('1080p'),
        greaterThan(SourceReport.qualityRank('720p')));
  });

  test('sorts playable first, then quality, latency and match score', () {
    final entries = [
      _entry('dead', status: SourceReportStatus.unreachable, quality: '4K'),
      _entry('slow', status: SourceReportStatus.reachable, quality: '720p',
          latency: const Duration(milliseconds: 900)),
      _entry('fast', status: SourceReportStatus.reachable, quality: '720p',
          latency: const Duration(milliseconds: 120)),
      _entry('best', status: SourceReportStatus.reachable, quality: '1080p',
          latency: const Duration(milliseconds: 500)),
      _entry('needs-sniff', status: SourceReportStatus.unresolved),
    ];
    SourceReport.sort(entries);
    expect(entries.map((entry) => entry.sourceName),
        ['best', 'fast', 'slow', 'needs-sniff', 'dead']);
  });

  test('lower match score loses only as the final tie-breaker', () {
    final entries = [
      _entry('a', status: SourceReportStatus.reachable, score: 0.5),
      _entry('b', status: SourceReportStatus.reachable, score: 0.9),
    ];
    SourceReport.sort(entries);
    expect(entries.first.sourceName, 'b');
  });

  test('detects player pages that mpv cannot open directly', () {
    expect(
      SourceReport.looksLikeLandingPage('https://example.test/vodplay/1-1-1.html'),
      isTrue,
    );
    expect(
      SourceReport.looksLikeLandingPage('https://example.test/play/abc'),
      isTrue,
    );
    expect(
      SourceReport.looksLikeLandingPage('https://example.test/abc/index.m3u8'),
      isFalse,
    );
  });

  testWidgets('renders a reachable source with quality and link',
      (tester) async {
    final adapter = _FakeAdapter();
    await tester.pumpWidget(MaterialApp(
      home: SourceReportPage(
        query: 'FX战士久留美',
        inputs: [
          SourceReportInput(
            adapter: adapter,
            items: [
              const MediaSummary(
                sourceId: 'fake:report',
                title: 'FX战士久留美',
                url: 'https://example.test/show',
              ),
            ],
          ),
        ],
        probe: (stream) async => ProbeResult(
          url: stream.url,
          reachable: true,
          latency: const Duration(milliseconds: 80),
        ),
        httpClient: MockClient((_) async => http.Response('no', 404)),
      ),
    ));
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.textContaining('可播放').evaluate().isNotEmpty) break;
    }

    expect(find.textContaining('可播放'), findsOneWidget);
    expect(find.textContaining('1080p'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });
}

class _FakeAdapter implements SourceAdapter {
  @override
  String get id => 'fake:report';

  @override
  String get name => '测试源';

  @override
  Future<List<MediaSummary>> search(String keyword) async => const [];

  @override
  Future<List<EpisodeGroup>> episodes(MediaSummary media) async => const [
        EpisodeGroup(
          name: '线路 1',
          episodes: [Episode(name: '第 1 集', url: 'https://example.test/ep1')],
        ),
      ];

  @override
  Future<PlayableStream?> resolve(Episode episode) async => PlayableStream(
        'https://example.test/first.m3u8',
        height: 1080,
      );
}
