import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/sources/tvbox/tvbox_config.dart';

void main() {
  test('keeps only plain HTTP TVBox sites', () {
    final sites = TvBoxConfigParser.sitesFromJson({
      'sites': [
        {'name': 'JSON', 'type': 1, 'api': 'https://example.test/api.php/provide/vod/'},
        {'name': 'XML', 'type': 0, 'api': 'https://example.test/xml'},
        {'name': 'Jar', 'type': 3, 'api': 'https://example.test/spider.jar'},
        {'name': 'NoApi', 'type': 1},
      ]
    });

    expect(sites, hasLength(2));
    expect(sites.first.name, 'JSON');
    expect(sites.first.type, 1);
  });

  test('deduplicates APIs and resolves relative paths', () {
    final sites = TvBoxConfigParser.sitesFromJson(
      {
        'sites': [
          {'name': 'A', 'type': 1, 'api': 'api.php'},
          {'name': 'B', 'type': 1, 'api': 'api.php'},
        ]
      },
      baseUri: Uri.parse('https://example.test/config/'),
    );
    expect(sites, hasLength(1));
    expect(sites.single.api, 'https://example.test/config/api.php');
  });

  test('parses warehouse URLs', () {
    final urls = TvBoxConfigParser.warehouseUrls({
      'urls': [
        {'name': 'a', 'url': 'https://example.test/a.json'},
        {'name': 'b', 'url': 'not a url'},
      ]
    });
    expect(urls, hasLength(1));
  });

  test('loads local config files and ignores broken ones', () async {
    final temp = Directory.systemTemp.createTempSync('praxino-tvbox-');
    addTearDown(() => temp.deleteSync(recursive: true));
    File('${temp.path}${Platform.pathSeparator}ok.json').writeAsStringSync(
      jsonEncode({
        'sites': [
          {'name': 'Local', 'type': 1, 'api': 'https://example.test/api'}
        ]
      }),
    );
    File('${temp.path}${Platform.pathSeparator}bad.json')
        .writeAsStringSync('not json');

    final sites = await TvBoxConfigLoader.loadDirectory(temp);
    expect(sites.single.name, 'Local');
  });
}
