import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Location of the optional libmpv/VapourSynth enhancement pack.
class EnhancePackPaths {
  EnhancePackPaths._();

  static String root({String? appData}) {
    final base = appData ??
        Platform.environment['APPDATA'] ??
        Directory.current.path;
    return p.join(base, 'Praxino', 'enhance-pack');
  }

  static String libmpv({String? appData}) =>
      p.join(root(appData: appData), 'libmpv-2.dll');

  static bool installed({String? appData}) =>
      File(libmpv(appData: appData)).existsSync();

  /// media_kit 1.2.x needs client API 2.1 or newer within major version 2;
  /// newer minors only add functions, so 2.6 builds work too.
  static bool isCompatibleVersion(int version) =>
      (version >> 16) == 2 && (version & 0xFFFF) >= 1;

  /// Checks the DLL's exported client API version before activating it.
  /// Call this only from the settings flow: it maps the DLL into the process.
  static bool compatible({String? appData}) {
    final path = libmpv(appData: appData);
    if (!File(path).existsSync()) return false;
    try {
      final library = DynamicLibrary.open(path);
      final version = library.lookupFunction<Uint32 Function(), int Function()>(
        'mpv_client_api_version',
      )();
      return isCompatibleVersion(version);
    } on Object {
      return false;
    }
  }
}
