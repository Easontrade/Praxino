import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/sources/webdav/webdav_client.dart';
import 'package:praxino/core/sources/webdav/webdav_playlist.dart';

WebDavEntry _entry(String path, {bool directory = false}) => WebDavEntry(
      path: path,
      name: path.split('/').last,
      isDirectory: directory,
    );

void main() {
  group('sortedWebDavEntries', () {
    test('puts folders before files and sorts EP2 before EP10', () {
      final sorted = sortedWebDavEntries([
        _entry('/Show/EP10.mkv'),
        _entry('/Show/EP2.mkv'),
        _entry('/Show/Season 2', directory: true),
        _entry('/Show/EP1.mkv'),
      ]);
      expect(sorted.map((e) => e.name), [
        'Season 2',
        'EP1.mkv',
        'EP2.mkv',
        'EP10.mkv',
      ]);
    });
  });

  test('webDavVideoEntries keeps videos in browser order', () {
    final videos = webDavVideoEntries([
      _entry('/Show/EP10.mkv'),
      _entry('/Show/EP2.mkv'),
      _entry('/Show/cover.jpg'),
      _entry('/Show/subs.ass'),
      _entry('/Show/Season 2', directory: true),
    ]);
    expect(videos.map((e) => e.name), ['EP2.mkv', 'EP10.mkv']);
  });

  test('isSiblingSubtitle accepts language suffixes only for that episode', () {
    expect(isSiblingSubtitle('Demo 01.ass', 'Demo 01.mkv'), isTrue);
    expect(isSiblingSubtitle('Demo 01.zh.ass', 'Demo 01.mkv'), isTrue);
    expect(isSiblingSubtitle('Demo 01_en.srt', 'Demo 01.mkv'), isTrue);
    expect(isSiblingSubtitle('Demo 01 - Chinese.ass', 'Demo 01.mkv'), isTrue);
    expect(isSiblingSubtitle('Demo 02.ass', 'Demo 01.mkv'), isFalse);
    expect(isSiblingSubtitle('Demo 010.ass', 'Demo 01.mkv'), isFalse);
    expect(isSiblingSubtitle('Demo 01.mkv', 'Demo 01.mkv'), isFalse);
  });

  test('subtitlePriority prefers Chinese, then English, then others', () {
    expect(subtitlePriority('Demo.zh.ass'), 0);
    expect(subtitlePriority('Demo.chs.srt'), 0);
    expect(subtitlePriority('Demo.中文.ass'), 0);
    expect(subtitlePriority('Demo.en.srt'), 1);
    expect(subtitlePriority('Demo.ja.ass'), 2);
  });

  test('webDavSubtitleUrls orders subtitles and keys them by video URL', () {
    final map = webDavSubtitleUrls(
      [
        _entry('/Show/EP2.mkv'),
        _entry('/Show/EP2.en.srt'),
        _entry('/Show/EP2.zh.ass'),
        _entry('/Show/EP2.ass'),
        _entry('/Show/EP1.mkv'),
        _entry('/Show/EP1.ja.ass'),
      ],
      uriFor: (path) => 'https://example.test/dav$path',
    );
    final ep2 = map['https://example.test/dav/Show/EP2.mkv']!;
    expect(ep2.keys, ['EP2.zh.ass', 'EP2.en.srt', 'EP2.ass']);
    expect(ep2.values.first, 'https://example.test/dav/Show/EP2.zh.ass');
    final ep1 = map['https://example.test/dav/Show/EP1.mkv']!;
    expect(ep1.keys, ['EP1.ja.ass']);
    expect(map, hasLength(2));
  });

  test('webDavHistoryKey omits credentials and query string', () {
    final key = webDavHistoryKey(Uri.parse(
      'https://user:secret@Example.TEST:8443/dav/%E7%94%B5%E5%BD%B1/a.mkv?token=1#part',
    ));
    expect(key, 'webdav:https://example.test:8443/dav/%E7%94%B5%E5%BD%B1/a.mkv');
    expect(key, isNot(contains('secret')));
    expect(key, isNot(contains('token')));
    expect(
      key,
      webDavHistoryKey(Uri.parse(
        'https://user:other@example.test:8443/dav/%E7%94%B5%E5%BD%B1/a.mkv?token=2',
      )),
    );
  });

  test('webDavHistoryKey keeps servers and paths apart', () {
    final a = webDavHistoryKey(Uri.parse('https://one.test/dav/EP1.mkv'));
    final b = webDavHistoryKey(Uri.parse('https://two.test/dav/EP1.mkv'));
    final c = webDavHistoryKey(Uri.parse('https://one.test/dav/EP2.mkv'));
    expect({a, b, c}, hasLength(3));
    expect(
      webDavHistoryKey(Uri.parse('https://one.test/dav/EP1.mkv/')),
      a,
    );
  });
}
