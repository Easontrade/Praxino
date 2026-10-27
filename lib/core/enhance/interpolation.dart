import 'package:path/path.dart' as p;

/// Frame interpolation backend selected by the user.
enum InterpolationMode {
  off(null),
  mvtools('mvtools_flowfps.vpy'),
  rife('rife_ncnn.vpy');

  const InterpolationMode(this.templateName);

  /// Bundled template under `assets/vapoursynth/`, or null for [off].
  final String? templateName;
}

/// The `.vpy` script to run for [mode]: the user's [override] when set,
/// otherwise the bundled template in [templateDir].
String? interpolationScriptFor(
  InterpolationMode mode, {
  required String templateDir,
  String? override,
}) {
  final name = mode.templateName;
  if (name == null) return null;
  if (override != null && override.trim().isNotEmpty) return override.trim();
  return p.join(templateDir, name);
}

/// Builds mpv's `vf` chain. Denoise and interpolation cannot each write `vf`
/// separately, so they are composed here in one place.
String buildVideoFilterChain({
  required bool denoise,
  required InterpolationMode interpolation,
  String? vapoursynthScript,
}) {
  final filters = <String>[];
  if (denoise) {
    filters.add('lavfi=[hqdn3d=1.2:1.0:6:6]');
  }
  if (interpolation != InterpolationMode.off &&
      vapoursynthScript != null &&
      vapoursynthScript.isNotEmpty) {
    filters.add('vapoursynth=$vapoursynthScript');
  }
  return filters.join(',');
}
