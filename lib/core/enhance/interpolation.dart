import 'package:path/path.dart' as p;

/// Frame interpolation backend selected by the user.
enum InterpolationMode {
  off(null),
  smooth(null),
  mvtools('mvtools_flowfps.vpy'),
  rife('rife_ncnn.vpy');

  const InterpolationMode(this.templateName);

  /// Bundled template under `assets/vapoursynth/`, or null for [off].
  final String? templateName;
}

/// RIFE output-rate strategy.
enum RifeProfile {
  double('2 倍帧率', 'RIFE 只推理一半帧，速度最快'),
  fixed60('固定 60fps', '低帧率源补到 60，推理量更大');

  const RifeProfile(this.label, this.hint);

  final String label;
  final String hint;
}

/// The `.vpy` script to run for [mode]: the user's [override] when set,
/// otherwise the bundled template in [templateDir].
String? interpolationScriptFor(
  InterpolationMode mode, {
  required String templateDir,
  String? override,
  RifeProfile profile = RifeProfile.double,
}) {
  final name = mode == InterpolationMode.rife && profile == RifeProfile.fixed60
      ? 'rife_ncnn_60.vpy'
      : mode.templateName;
  if (name == null) return null;
  if (override != null && override.trim().isNotEmpty) return override.trim();
  return p.join(templateDir, name);
}

/// Builds mpv's `vf` chain. Denoise now runs as a GPU shader (the bundled
/// libmpv has no hqdn3d), so only VapourSynth contributes here.
String buildVideoFilterChain({
  required InterpolationMode interpolation,
  String? vapoursynthScript,
}) {
  final filters = <String>[];
  if (interpolation != InterpolationMode.off &&
      interpolation != InterpolationMode.smooth &&
      vapoursynthScript != null &&
      vapoursynthScript.isNotEmpty) {
    filters.add('vapoursynth=$vapoursynthScript');
  }
  return filters.join(',');
}
