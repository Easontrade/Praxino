import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:praxino/core/enhance/enhance_pack_activation.dart';

void main() {
  late Directory app;
  late File pack;
  late EnhancePackActivation activation;

  File inApp(String name) => File(p.join(app.path, name));

  setUp(() {
    final temp = Directory.systemTemp.createTempSync('praxino-activate-');
    app = Directory(p.join(temp.path, 'app'))..createSync();
    inApp('libmpv-2.dll').writeAsBytesSync([1, 1, 1]);
    pack = File(p.join(temp.path, 'pack.dll'))..writeAsBytesSync([2, 2, 2, 2]);
    activation = EnhancePackActivation(appDir: app.path);
    addTearDown(() => temp.deleteSync(recursive: true));
  });

  test('activation puts the pack in place and keeps the bundled DLL', () {
    expect(activation.isActive, isFalse);
    expect(activation.activate(pack.path), isTrue);

    expect(activation.isActive, isTrue);
    expect(inApp('libmpv-2.dll').readAsBytesSync(), [2, 2, 2, 2]);
    expect(inApp('libmpv-2.media_kit.dll').readAsBytesSync(), [1, 1, 1]);
  });

  test('activating the same pack twice is a no-op', () {
    activation.activate(pack.path);
    expect(activation.activate(pack.path), isFalse);
    expect(inApp('libmpv-2.media_kit.dll').readAsBytesSync(), [1, 1, 1]);
  });

  test('a newer pack replaces the old one without losing the backup', () {
    activation.activate(pack.path);
    pack.writeAsBytesSync([3, 3]);

    expect(activation.activate(pack.path), isTrue);
    expect(inApp('libmpv-2.dll').readAsBytesSync(), [3, 3]);
    expect(inApp('libmpv-2.media_kit.dll').readAsBytesSync(), [1, 1, 1]);
  });

  test('deactivation restores the bundled DLL and stale files get cleaned', () {
    activation.activate(pack.path);
    expect(activation.deactivate(), isTrue);

    expect(activation.isActive, isFalse);
    expect(inApp('libmpv-2.dll').readAsBytesSync(), [1, 1, 1]);
    final stale = app.listSync().where((e) => e.path.endsWith('.stale'));
    expect(stale, hasLength(1));

    activation.cleanUpStale();
    expect(app.listSync().where((e) => e.path.endsWith('.stale')), isEmpty);
    expect(activation.deactivate(), isFalse);
  });

  test('missing pack file is reported', () {
    expect(() => activation.activate(p.join(app.path, 'missing.dll')),
        throwsA(isA<FileSystemException>()));
    expect(activation.isActive, isFalse);
  });
}
