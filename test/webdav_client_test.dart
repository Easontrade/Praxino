import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxino/core/sources/source_adapter.dart';
import 'package:praxino/core/sources/webdav/webdav_adapter.dart';
import 'package:praxino/core/sources/webdav/webdav_client.dart';

const _xml = '''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/dav/</D:href>
    <D:propstat><D:prop><D:displayname>/</D:displayname><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/%E7%94%B5%E5%BD%B1%20%E5%90%88%E9%9B%86/</D:href>
    <D:propstat><D:prop><D:displayname>电影 合集</D:displayname><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat>
  </D:response>
  <D:response>
    <D:href>/dav/%E7%94%B5%E5%BD%B1%20%E5%90%88%E9%9B%86/Demo%2001.mkv</D:href>
    <D:propstat><D:prop><D:displayname>Demo 01.mkv</D:displayname><D:resourcetype/><D:getcontentlength>123</D:getcontentlength><D:getcontenttype>video/x-matroska</D:getcontenttype></D:prop></D:propstat>
  </D:response>
</D:multistatus>''';

void main() {
  test('parses namespaced PROPFIND and decodes Chinese paths', () async {
    final client = WebDavClient(
      baseUrl: 'https://example.test/dav',
      username: 'user',
      password: 'pass',
      client: MockClient((request) async {
        expect(request.method, 'PROPFIND');
        expect(request.headers['Depth'], '1');
        expect(request.headers['Authorization'], startsWith('Basic '));
        return http.Response.bytes(utf8.encode(_xml), 207,
            headers: {'content-type': 'application/xml; charset=utf-8'});
      }),
    );
    final entries = await client.list('/');
    expect(entries.map((entry) => entry.name), contains('电影 合集'));
    expect(entries.any((entry) => entry.isDirectory), isTrue);
  });

  test('encodes paths with Chinese and spaces', () {
    final client = WebDavClient(
      baseUrl: 'https://example.test/dav',
      username: 'u',
      password: 'p',
    );
    final uri = client.uriFor('/电影 合集/Demo 01.mkv');
    expect(uri.toString(), contains('%E7%94%B5%E5%BD%B1%20%E5%90%88%E9%9B%86'));
    expect(uri.toString(), contains('Demo%2001.mkv'));
    client.close();
  });

  test('401 becomes WebDavAuthException', () async {
    final client = WebDavClient(
      baseUrl: 'https://example.test/dav',
      username: 'u',
      password: 'p',
      client: MockClient((_) async => http.Response('no', 401)),
    );
    expect(() => client.list('/'), throwsA(isA<WebDavAuthException>()));
    client.close();
  });

  test('adapter lists same-directory videos and streams with auth headers',
      () async {
    final client = WebDavClient(
      baseUrl: 'https://example.test/dav',
      username: 'user',
      password: 'secret',
      client: MockClient((_) async => http.Response.bytes(utf8.encode(_xml), 207)),
    );
    final adapter = WebDavAdapter(name: 'OpenList', client: client);
    final groups = await adapter.episodes(const MediaSummary(
      sourceId: 'webdav:OpenList',
      title: 'Demo',
      url: '/电影 合集/Demo 01.mkv',
    ));
    expect(groups.single.episodes.single.name, 'Demo 01.mkv');
    final stream = await adapter.resolve(groups.single.episodes.single);
    expect(stream!.headers['Authorization'], startsWith('Basic '));
    expect(stream.url, contains('Demo%2001.mkv'));
    expect(stream.url, isNot(contains('secret')));
    client.close();
  });
}
