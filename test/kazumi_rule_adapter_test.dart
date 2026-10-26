import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxino/core/sources/kazumi/kazumi_rule.dart';
import 'package:praxino/core/sources/kazumi/kazumi_rule_adapter.dart';
import 'package:praxino/core/sources/source_adapter.dart';

const _searchHtml = '''
<html><body><ul class="list">
  <li><a class="t" href="/detail/1.html">Example Show</a></li>
  <li><a class="t" href="/detail/2.html">Example Show 2</a></li>
</ul></body></html>''';

const _detailHtml = '''
<html><body>
  <ul class="road"><li><a href="/play/1-1.html">第01集</a></li>
                   <li><a href="/play/1-2.html">第02集</a></li></ul>
  <ul class="road"><li><a href="/play/2-1.html">第01集</a></li></ul>
</body></html>''';

http.Response _utf8(String body, [Map<String, String>? headers]) =>
    http.Response.bytes(utf8.encode(body), 200, headers: headers ?? {});

void main() {
  test('xpath rule: search and episodes', () async {
    final rule = KazumiRule.parseAll(jsonDecode('''[{
      "name": "demo", "version": "1", "baseURL": "https://example.test/",
      "searchURL": "https://example.test/search?wd=@keyword",
      "searchList": "//ul[@class='list']/li", "searchName": "//a",
      "searchResult": "//a", "chapterRoads": "//ul[@class='road']",
      "chapterResult": "//li/a"
    }]''')).single;

    final adapter = KazumiRuleAdapter(rule, client: MockClient((req) async {
      if (req.url.path == '/search') {
        expect(req.url.queryParameters['wd'], '示例');
        return _utf8(_searchHtml);
      }
      return _utf8(_detailHtml);
    }));

    final hits = await adapter.search('示例');
    expect(hits.map((h) => h.title), ['Example Show', 'Example Show 2']);
    expect(hits.first.url, 'https://example.test/detail/1.html');

    final groups = await adapter.episodes(hits.first);
    expect(groups, hasLength(2));
    expect(groups.first.episodes.map((e) => e.name), ['第01集', '第02集']);
    expect(groups.first.episodes.first.url,
        'https://example.test/play/1-1.html');

    // Webview rules hand resolution to a StreamSniffer.
    expect(await adapter.resolve(groups.first.episodes.first), isNull);
  });

  test('api rule: search and nested episodes', () async {
    final rule = KazumiRule.fromJson(jsonDecode('''{
      "name": "api-demo", "version": "1", "baseURL": "https://example.test/",
      "searchMode": "api", "chapterMode": "api",
      "searchApiConfig": {
        "request": {"method": "POST", "url": "https://api.example.test/search",
                    "bodyType": "json", "body": {"q": "@keyword"}},
        "listPath": "\$[*]", "namePath": "\$.title", "sourcePath": "\$.id"
      },
      "chapterApiConfig": {
        "request": {"method": "POST", "url": "https://api.example.test/detail",
                    "bodyType": "json", "body": {"id": "@source"}},
        "format": "nested", "roadsPath": "\$.sources[*]",
        "roadNamePath": "\$.name", "episodesPath": "\$.episodes[*]",
        "episodeNamePath": "\$.title", "episodeUrlPath": "\$.id",
        "episodePage": {"url": "https://example.test/a/@source/p/@episodeUrl"}
      }
    }''') as Map<String, dynamic>);

    final adapter = KazumiRuleAdapter(rule, client: MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      if (req.url.path == '/search') {
        expect(body['q'], 'abc');
        return _utf8(jsonEncode([
          {'id': 42, 'title': 'Api Show'}
        ]));
      }
      expect(body['id'], '42');
      return _utf8(jsonEncode({
        'sources': [
          {
            'name': 'Line A',
            'episodes': [
              {'id': 7, 'title': 'EP1'}
            ]
          }
        ]
      }));
    }));

    final hits = await adapter.search('abc');
    expect(hits.single.title, 'Api Show');
    final groups = await adapter.episodes(hits.single);
    expect(groups.single.name, 'Line A');
    expect(groups.single.episodes.single.url, 'https://example.test/a/42/p/7');
    expect(adapter, isA<SourceAdapter>());
  });
}
