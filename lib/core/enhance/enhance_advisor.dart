import 'enhance_settings.dart';

/// Suggests a lower upscale preset when the GPU cannot keep up.
///
/// Pure timing/ratio logic: the caller passes mpv samples and applies the
/// returned preset. A user's manual choice suppresses suggestions for
/// [userOverride].
class EnhanceAdvisor {
  EnhanceAdvisor({
    this.maxDropRatio = 0.05,
    this.window = const Duration(seconds: 3),
    this.userOverride = const Duration(minutes: 30),
  });

  final double maxDropRatio;
  final Duration window;
  final Duration userOverride;

  DateTime? _sampleAt;
  int _dropsAtStart = 0;
  DateTime? _userChoiceAt;

  bool hasUserOverride(DateTime now) =>
      _userChoiceAt != null && now.difference(_userChoiceAt!) < userOverride;

  void noteUserChoice(DateTime now) {
    _userChoiceAt = now;
    _sampleAt = null;
  }

  /// Returns the next lower preset, or null when no change is warranted.
  UpscalePreset? evaluate({
    required UpscalePreset current,
    required int droppedFrames,
    required double fps,
    required DateTime now,
  }) {
    if (hasUserOverride(now)) return null;

    final sampleAt = _sampleAt;
    if (sampleAt == null) {
      _sampleAt = now;
      _dropsAtStart = droppedFrames;
      return null;
    }
    final elapsed = now.difference(sampleAt);
    if (elapsed < window) return null;

    final drops = droppedFrames - _dropsAtStart;
    _sampleAt = now;
    _dropsAtStart = droppedFrames;

    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final expected = (fps > 0 ? fps : 60) * seconds;
    if (expected <= 0) return null;
    if (drops / expected <= maxDropRatio) return null;
    return lower(current);
  }

  static UpscalePreset? lower(UpscalePreset current) => switch (current) {
        UpscalePreset.anime4kQuality => UpscalePreset.anime4kBalanced,
        UpscalePreset.anime4kBalanced => UpscalePreset.anime4kFast,
        UpscalePreset.anime4kFast => UpscalePreset.off,
        UpscalePreset.fsrcnnx => UpscalePreset.off,
        UpscalePreset.off => null,
      };
}
