import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/process/process_runner.dart';
import 'package:praxino/core/sources/source_adapter.dart';
import 'package:praxino/core/sources/ytdlp/ytdlp_adapter.dart';

class _FakeRunner implements ProcessRunner {
  _FakeRunner(this.output);

  final ProcessOutput output;
  List<String> arguments = const [];
  int calls = 0;

  @override
  Future<ProcessOutput> run(String executable, List<String> args) async {
    calls++;
    arguments = args;
    return output;
  }
}

ProcessOutput _out(Object json, {int exitCode = 0}) => ProcessOutput(
      exitCode: exitCode,
      stdout: jsonEncode(json),
      stderr: '',
    );

const _combined = {
  'title': '示例视频',
  'subtitles': {
    'zh-Hans': [
      {'url': 'https://example.test/zh.vtt', 'ext': 'vtt'}
    ],
    'en': [
      {'url': 'https://example.test/en.vtt', 'ext': 'vtt'}
    ],
  },
  'automatic_captions': {
    'ja': [
      {'url': 'https://example.test/ja.vtt'}
    ]
  },
  'formats': [
    {
      'url': 'https://example.test/720.mp4',
      'vcodec': 'avc1',
      'acodec': 'mp4a',
      'height': 720,
      'tbr': 1500,
    },
    {
      'url': 'https://example.test/1080.mp4',
      'vcodec': 'avc1',
      'acodec': 'mp4a',
      'height': 1080,
      'tbr': 3000,
      'http_headers': {'Referer': 'https://example.test/'},
    },
  ],
};

const _separate = {
  'formats': [
    {
      'url': 'https://example.test/video.mp4',
      'vcodec': 'avc1',
      'acodec': 'none',
      'height': 1080,
      'tbr': 2500,
    },
    {
      'url': 'https://example.test/audio.m4a',
      'vcodec': 'none',
      'acodec': 'mp4a',
      'abr': 128,
    },
  ],
};

void main() {
  test('picks the best combined format with quality and headers', () async {
    final runner = _FakeRunner(_out(_combined));
    final adapter = YtDlpAdapter(runner: runner);

    final stream = await adapter.resolve(const Episode(
      name: '示例视频',
      url: 'https://example.test/watch',
    ));

    expect(runner.arguments, ['-J', '--no-playlist', 'https://example.test/watch']);
    expect(stream!.url, 'https://example.test/1080.mp4');
    expect(stream.height, 1080);
    expect(stream.bitrateKbps, 3000);
    expect(stream.headers['Referer'], 'https://example.test/');
    expect(stream.subtitleLanguages, containsAll(['zh-Hans', 'en', 'ja']));
    expect(stream.subtitleLanguages.first, 'zh-Hans');
    expect(stream.subtitleUrls['zh-Hans'], 'https://example.test/zh.vtt');
    expect(stream.subtitleUrls['ja'], 'https://example.test/ja.vtt');
  });

  test('falls back to video + separate audio', () async {
    final adapter = YtDlpAdapter(runner: _FakeRunner(_out(_separate)));

    final stream = await adapter.resolve(const Episode(
      name: '示例视频',
      url: 'https://example.test/watch',
    ));

    expect(stream!.url, 'https://example.test/video.mp4');
    expect(stream.audioUrl, 'https://example.test/audio.m4a');
    expect(stream.height, 1080);
  });

  test('surfaces yt-dlp failures', () async {
    final adapter = YtDlpAdapter(
      runner: _FakeRunner(const ProcessOutput(
        exitCode: 1,
        stdout: '',
        stderr: 'ERROR: unsupported URL',
      )),
    );

    expect(
      () => adapter.resolve(const Episode(
        name: 'x',
        url: 'https://example.test/watch',
      )),
      throwsA(isA<YtDlpException>()),
    );
  });

  test('a URL search returns one hit without invoking yt-dlp', () async {
    final runner = _FakeRunner(_out({}));
    final adapter = YtDlpAdapter(runner: runner);

    final hits = await adapter.search('https://example.test/watch');

    expect(hits.single.url, 'https://example.test/watch');
    expect(runner.calls, 0);
  });

  test('a keyword search parses ytsearch entries', () async {
    final runner = _FakeRunner(_out({
      'entries': [
        {'title': 'A', 'webpage_url': 'https://example.test/a'},
        {'title': 'B', 'url': 'https://example.test/b'},
      ],
    }));
    final adapter = YtDlpAdapter(runner: runner);

    final hits = await adapter.search('示例');

    expect(runner.arguments, ['-J', '--flat-playlist', 'ytsearch5:示例']);
    expect(hits.map((hit) => hit.url),
        ['https://example.test/a', 'https://example.test/b']);
  });
}
