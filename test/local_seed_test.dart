import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/storage/local_seed.dart';

void main() {
  test('reads subscriptions from a local seed file', () async {
    final temp = Directory.systemTemp.createTempSync('praxino-seed-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final file = File('${temp.path}${Platform.pathSeparator}seed.json');
    file.writeAsStringSync(jsonEncode([
      {
        'url': 'local://kazumi-default',
        'name': 'Kazumi 默认规则',
        'enabled': true,
        'rules': [
          {'name': 'demo', 'baseURL': 'https://example.test/'}
        ],
      }
    ]));

    final subscriptions = await LocalSeed.read(path: file.path);
    expect(subscriptions.single.name, 'Kazumi 默认规则');
    expect(subscriptions.single.rules.single['name'], 'demo');
  });

  test('accepts a single subscription object', () async {
    final temp = Directory.systemTemp.createTempSync('praxino-seed-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final file = File('${temp.path}${Platform.pathSeparator}seed.json');
    file.writeAsStringSync(jsonEncode({
      'url': 'local://single',
      'name': 'single',
      'rules': [
        {'name': 'demo', 'baseURL': 'https://example.test/'}
      ],
    }));

    final subscriptions = await LocalSeed.read(path: file.path);
    expect(subscriptions.single.url, 'local://single');
  });

  test('missing or broken seed files are ignored', () async {
    expect(await LocalSeed.read(path: 'Z:/definitely/missing.json'), isEmpty);

    final temp = Directory.systemTemp.createTempSync('praxino-seed-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final file = File('${temp.path}${Platform.pathSeparator}seed.json')
      ..writeAsStringSync('not json');
    expect(await LocalSeed.read(path: file.path), isEmpty);
  });
}
