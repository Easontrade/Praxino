import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/enhance/enhance_pack_paths.dart';

void main() {
  test('uses the app-data/Praxino/enhance-pack layout', () {
    final root = EnhancePackPaths.root(appData: r'C:\Users\demo\AppData\Roaming');
    expect(root, endsWith(r'Praxino\enhance-pack'));
    expect(EnhancePackPaths.libmpv(appData: root),
        endsWith(r'libmpv-2.dll'));
  });

  test('accepts client API 2.1 and newer 2.x builds', () {
    expect(EnhancePackPaths.isCompatibleVersion((2 << 16) | 1), isTrue);
    expect(EnhancePackPaths.isCompatibleVersion((2 << 16) | 6), isTrue);
    expect(EnhancePackPaths.isCompatibleVersion((2 << 16) | 0), isFalse);
    expect(EnhancePackPaths.isCompatibleVersion((1 << 16) | 109), isFalse);
    expect(EnhancePackPaths.isCompatibleVersion((3 << 16) | 0), isFalse);
  });

  test('reports whether the DLL is installed', () {    final temp = Directory.systemTemp.createTempSync('praxino-pack-');
    addTearDown(() => temp.deleteSync(recursive: true));

    expect(EnhancePackPaths.installed(appData: temp.path), isFalse);
    final dir = Directory(EnhancePackPaths.root(appData: temp.path))
      ..createSync(recursive: true);
    File('${dir.path}${Platform.pathSeparator}libmpv-2.dll').writeAsBytesSync([1]);
    expect(EnhancePackPaths.installed(appData: temp.path), isTrue);
  });
}
