import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// Where a portable VapourSynth install lives.
///
/// mpv loads `VSScript.dll` (and through it Python) only when the
/// `vapoursynth` filter is first created, so setting the process environment
/// at startup is enough; users don't have to edit system variables.
class VapourSynthRuntime {
  const VapourSynthRuntime({required this.pythonDir, required this.siteDir});

  /// Directory containing `python3xx.dll` / `python.exe`.
  final String pythonDir;

  /// The `site-packages/vapoursynth` directory (holds `VSScript.dll` and
  /// `plugins/`).
  final String siteDir;

  bool get isConfigured => pythonDir.isNotEmpty && siteDir.isNotEmpty;

  /// The variables to set, given the current [path] value.
  Map<String, String> environment(String path) => {
        'PATH': [pythonDir, siteDir, path].where((e) => e.isNotEmpty).join(';'),
        'PYTHONPATH': p.dirname(siteDir),
        'VAPOURSYNTH_PLUGIN_PATH': p.join(siteDir, 'plugins'),
      };

  /// Sets [environment] on the running process (Windows only).
  ///
  /// Both copies of the environment are updated: the Win32 block (used by
  /// `LoadLibrary` to find `VSScript.dll` via PATH) and the shared C runtime's
  /// table, which Python reads `PYTHONPATH` from and which does not see
  /// `SetEnvironmentVariableW` changes once initialised.
  void applyToProcess() {
    if (!Platform.isWindows || !isConfigured) return;
    _preloadSystemVulkan();
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final setWin32 = kernel32.lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Utf16>),
        int Function(Pointer<Utf16>, Pointer<Utf16>)>('SetEnvironmentVariableW');
    final ucrt = DynamicLibrary.open('ucrtbase.dll');
    final setCrt = ucrt.lookupFunction<
        Int32 Function(Pointer<Utf16>, Pointer<Utf16>),
        int Function(Pointer<Utf16>, Pointer<Utf16>)>('_wputenv_s');
    final vars = environment(Platform.environment['PATH'] ?? '');
    for (final entry in vars.entries) {
      final name = entry.key.toNativeUtf16();
      final value = entry.value.toNativeUtf16();
      setWin32(name, value);
      setCrt(name, value);
      malloc.free(name);
      malloc.free(value);
    }
  }

  /// The Flutter engine ships a dev-build `vulkan-1.dll` (for ANGLE's
  /// SwiftShader fallback) next to the executable. GPU filters such as RIFE
  /// (ncnn) load `vulkan-1.dll` by name, which would resolve to that copy and
  /// crash. Loading the system loader by full path first makes every later
  /// by-name load reuse it.
  static void _preloadSystemVulkan() {
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final loader = p.join(root, 'System32', 'vulkan-1.dll');
    if (!File(loader).existsSync()) return;
    try {
      DynamicLibrary.open(loader);
    } on ArgumentError {
      // No usable system Vulkan; GPU filters will report their own error.
    }
  }
}
