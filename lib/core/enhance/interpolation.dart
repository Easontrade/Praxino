/// Frame interpolation backend selected by the user.
enum InterpolationMode { off, mvtools, rife }

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
