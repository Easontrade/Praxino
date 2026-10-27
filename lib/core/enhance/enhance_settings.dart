/// Real-time picture enhancement, applied through mpv properties.
///
/// Everything here runs inside the mpv render pipeline (GLSL hooks and
/// VapourSynth), so it works on any GPU without CUDA. Heavier, offline-quality
/// processing (Real-ESRGAN, RIFE) is a separate pipeline; see docs/ROADMAP.md.
library;

import 'interpolation.dart';

/// Anime4K v4 "Mode A" chains at three cost tiers.
///
/// The chains follow the upstream recommendations in
/// https://github.com/bloc97/Anime4K/blob/master/md/GLSL_Instructions_Advanced.md
enum UpscalePreset {
  off('关闭', '原始画面，只用 mpv 的高质量缩放'),
  anime4kFast('Anime4K 流畅', '核显 / 入门独显，CNN-S'),
  anime4kBalanced('Anime4K 均衡', '主流独显，CNN-M'),
  anime4kQuality('Anime4K 高质量', '高端独显，CNN-VL'),
  fsrcnnx('FSRCNNX 实拍', '实拍片专用，减少 Anime4K 的涂抹');

  const UpscalePreset(this.label, this.hint);

  final String label;
  final String hint;

  /// Shader file names under `assets/shaders/anime4k/`, in hook order.
  List<String> get shaders => switch (this) {
        off => const [],
        anime4kFast => const [
            'Anime4K_Clamp_Highlights.glsl',
            'Anime4K_Restore_CNN_S.glsl',
            'Anime4K_Upscale_CNN_x2_S.glsl',
            'Anime4K_AutoDownscalePre_x2.glsl',
            'Anime4K_AutoDownscalePre_x4.glsl',
            'Anime4K_Upscale_CNN_x2_S.glsl',
          ],
        anime4kBalanced => const [
            'Anime4K_Clamp_Highlights.glsl',
            'Anime4K_Restore_CNN_M.glsl',
            'Anime4K_Upscale_CNN_x2_M.glsl',
            'Anime4K_AutoDownscalePre_x2.glsl',
            'Anime4K_AutoDownscalePre_x4.glsl',
            'Anime4K_Upscale_CNN_x2_S.glsl',
          ],
        anime4kQuality => const [
            'Anime4K_Clamp_Highlights.glsl',
            'Anime4K_Restore_CNN_VL.glsl',
            'Anime4K_Upscale_CNN_x2_VL.glsl',
            'Anime4K_AutoDownscalePre_x2.glsl',
            'Anime4K_AutoDownscalePre_x4.glsl',
            'Anime4K_Upscale_CNN_x2_M.glsl',
          ],
        fsrcnnx => const ['FSRCNNX_x2_16-0-4-1.glsl'],
      };

  /// Asset subdirectory that holds this preset's shader files.
  String get shaderFamily =>
      this == UpscalePreset.fsrcnnx ? 'fsrcnnx' : 'anime4k';

  bool get isLiveAction => this == UpscalePreset.fsrcnnx;
}

/// The full enhancement state of one player.
class EnhanceSettings {
  const EnhanceSettings({
    this.upscale = UpscalePreset.off,
    this.deband = false,
    this.denoise = false,
    this.interpolation = InterpolationMode.off,
    this.rifeProfile = RifeProfile.double,
  });

  final UpscalePreset upscale;

  /// Removes colour banding in flat areas of low-bitrate encodes.
  final bool deband;

  /// Light GPU denoise against mosquito noise and blocking. Runs as a shader
  /// in the render pipeline, so hardware decoding stays enabled.
  final bool denoise;

  /// Frame interpolation backend; it only takes effect when a VapourSynth
  /// script is supplied to [toMpvProperties].
  final InterpolationMode interpolation;

  /// RIFE output-rate strategy; ignored for mvtools/off.
  final RifeProfile rifeProfile;

  bool get isOff =>
      upscale == UpscalePreset.off &&
      !deband &&
      !denoise &&
      interpolation == InterpolationMode.off;

  EnhanceSettings copyWith({
    UpscalePreset? upscale,
    bool? deband,
    bool? denoise,
    InterpolationMode? interpolation,
    RifeProfile? rifeProfile,
  }) =>
      EnhanceSettings(
        upscale: upscale ?? this.upscale,
        deband: deband ?? this.deband,
        denoise: denoise ?? this.denoise,
        interpolation: interpolation ?? this.interpolation,
        rifeProfile: rifeProfile ?? this.rifeProfile,
      );

  /// The mpv properties that realise these settings.
  ///
  /// [shaderDir] is the directory holding the Anime4K shader files,
  /// [listSeparator] is mpv's path-list separator (`;` on Windows, `:` elsewhere)
  /// [vapoursynthScript] is the `.vpy` path when interpolation is enabled and
  /// [denoiseShader] is the bundled GPU denoise shader.
  Map<String, String> toMpvProperties({
    required String shaderDir,
    required String listSeparator,
    String? vapoursynthScript,
    String? denoiseShader,
  }) {
    final filters = buildVideoFilterChain(
      interpolation: interpolation,
      vapoursynthScript: vapoursynthScript,
    );
    final shaders = [
      for (final name in upscale.shaders) '$shaderDir/$name',
    ];
    if (denoise && denoiseShader != null && denoiseShader.isNotEmpty) {
      shaders.insert(0, denoiseShader);
    }
    final interpolating = filters.contains('vapoursynth=');
    return {
      'glsl-shaders': shaders.join(listSeparator),
      'deband': deband ? 'yes' : 'no',
      if (deband) 'deband-iterations': '2',
      if (deband) 'deband-threshold': '40',
      if (deband) 'deband-grain': '16',
      'vf': filters,
      'hwdec': interpolating ? 'auto-copy' : 'auto-safe',
      // VapourSynth replaces the video timestamps. Audio-master sync then
      // drifts and can mute/drop audio; display-resample keeps audio and video
      // locked to the display clock instead.
      if (interpolating) 'video-sync': 'display-resample',
      if (interpolating) 'audio-pitch-correction': 'yes',
    };
  }

  Map<String, Object> toJson() => {
        'upscale': upscale.name,
        'deband': deband,
        'denoise': denoise,
        'interpolation': interpolation.name,
        'rifeProfile': rifeProfile.name,
      };

  factory EnhanceSettings.fromJson(Map<String, Object?> json) =>
      EnhanceSettings(
        upscale: UpscalePreset.values.firstWhere(
          (p) => p.name == json['upscale'],
          orElse: () => UpscalePreset.off,
        ),
        deband: json['deband'] == true,
        denoise: json['denoise'] == true,
        interpolation: InterpolationMode.values.firstWhere(
          (m) => m.name == json['interpolation'],
          orElse: () => InterpolationMode.off,
        ),
        rifeProfile: RifeProfile.values.firstWhere(
          (profile) => profile.name == json['rifeProfile'],
          orElse: () => RifeProfile.double,
        ),
      );

  @override
  bool operator ==(Object other) =>
      other is EnhanceSettings &&
      other.upscale == upscale &&
      other.deband == deband &&
      other.denoise == denoise &&
      other.interpolation == interpolation &&
      other.rifeProfile == rifeProfile;

  @override
  int get hashCode => Object.hash(upscale, deband, denoise, interpolation, rifeProfile);
}
