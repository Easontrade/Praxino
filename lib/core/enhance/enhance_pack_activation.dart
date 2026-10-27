import 'dart:io';

import 'package:path/path.dart' as p;

/// Puts the enhancement-pack libmpv in place of the bundled one.
///
/// `media_kit_video_plugin.dll` imports `libmpv-2.dll` by name, and Windows
/// resolves that from the application directory before `main()` runs. Loading
/// a second libmpv from elsewhere (`MediaKit.ensureInitialized(libmpv: ...)`)
/// leaves two copies in the process: the player is created with one and
/// rendered with the other, which crashes. So the pack has to *be* the
/// application's `libmpv-2.dll`.
///
/// Windows lets a loaded DLL be renamed (not overwritten), so activation works
/// while the app is running and takes effect on the next start.
class EnhancePackActivation {
  EnhancePackActivation({String? appDir})
      : appDir = appDir ?? p.dirname(Platform.resolvedExecutable);

  final String appDir;

  static const _dll = 'libmpv-2.dll';
  static const _bundledBackup = 'libmpv-2.media_kit.dll';
  static const _staleSuffix = '.stale';

  File get _current => File(p.join(appDir, _dll));
  File get _backup => File(p.join(appDir, _bundledBackup));

  /// Whether the application directory currently holds the pack's libmpv.
  bool get isActive => _backup.existsSync();

  /// Copies [packDll] over the application's libmpv, keeping the bundled one
  /// as a backup. Returns `false` when it was already active with this file.
  bool activate(String packDll) {
    final pack = File(packDll);
    if (!pack.existsSync()) {
      throw FileSystemException('增强包文件不存在', packDll);
    }
    if (isActive && _sameFile(pack, _current)) return false;
    if (_current.existsSync()) {
      if (isActive) {
        // A previous pack is in place; set it aside, keep the bundled backup.
        _moveAside(_current);
      } else {
        _current.renameSync(_backup.path);
      }
    }
    pack.copySync(_current.path);
    return true;
  }

  /// Restores the bundled libmpv. Returns `false` when nothing was active.
  bool deactivate() {
    if (!isActive) return false;
    if (_current.existsSync()) _moveAside(_current);
    _backup.renameSync(_current.path);
    return true;
  }

  /// Deletes DLLs set aside by earlier swaps; they are only deletable once the
  /// process that had them loaded has exited, so call this at startup.
  void cleanUpStale() {
    final dir = Directory(appDir);
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync()) {
      if (entity is File && entity.path.endsWith(_staleSuffix)) {
        try {
          entity.deleteSync();
        } on FileSystemException {
          // Still loaded by another instance; try again next start.
        }
      }
    }
  }

  void _moveAside(File file) {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    file.renameSync('${file.path}.$stamp$_staleSuffix');
  }

  static bool _sameFile(File a, File b) {
    if (!b.existsSync() || a.lengthSync() != b.lengthSync()) return false;
    final x = a.readAsBytesSync();
    final y = b.readAsBytesSync();
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }
}
