/// Real-time picture enhancement, applied through mpv properties.
///
/// Everything here runs inside the mpv render pipeline (GLSL hooks and lavfi
/// filters), so it works on any GPU without CUDA. Heavier, offline-quality
/// processing (Real-ESRGAN, RIFE) is a separate pipeline; see docs/ROADMAP.md.
library;

/// Anime4K v4 "Mode A" chains at three cost tiers.
///
/// The chains follow the upstream recommendations in
/// https://github.com/bloc97/Anime4K/blob/master/md/GLSL_Instructions_Advanced.md
enum UpscalePreset {
  off('关闭', '原始画面，只用 mpv 的高质量缩放'),
  anime4kFast('Anime4K 流畅', '核显 / 入门独显，CNN-S'),
  anime4kBalanced('Anime4K 均衡', '主流独显，CNN-M'),
  anime4kQuality('Anime4K 高质量', '高端独显，CNN-VL');

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
      };
}

/// The full enhancement state of one player.
class EnhanceSettings {
  const EnhanceSettings({
    this.upscale = UpscalePreset.off,
    this.deband = false,
    this.denoise = false,
  });

  final UpscalePreset upscale;

  /// Removes colour banding in flat areas of low-bitrate encodes.
  final bool deband;

  /// Light spatio-temporal denoise (hqdn3d) against mosquito noise and blocking.
  /// Needs frames in system memory, so it switches hardware decoding to a
  /// copy-back mode.
  final bool denoise;

  bool get isOff => upscale == UpscalePreset.off && !deband && !denoise;

  EnhanceSettings copyWith({
    UpscalePreset? upscale,
    bool? deband,
    bool? denoise,
  }) =>
      EnhanceSettings(
        upscale: upscale ?? this.upscale,
        deband: deband ?? this.deband,
        denoise: denoise ?? this.denoise,
      );

  /// The mpv properties that realise these settings.
  ///
  /// [shaderDir] is the directory holding the Anime4K shader files and
  /// [listSeparator] is mpv's path-list separator (`;` on Windows, `:` elsewhere).
  Map<String, String> toMpvProperties({
    required String shaderDir,
    required String listSeparator,
  }) {
    return {
      'glsl-shaders': upscale.shaders
          .map((name) => '$shaderDir/$name')
          .join(listSeparator),
      'deband': deband ? 'yes' : 'no',
      if (deband) 'deband-iterations': '2',
      if (deband) 'deband-threshold': '40',
      if (deband) 'deband-grain': '16',
      'vf': denoise ? 'lavfi=[hqdn3d=1.2:1.0:6:6]' : '',
      'hwdec': denoise ? 'auto-copy' : 'auto-safe',
    };
  }

  Map<String, Object> toJson() => {
        'upscale': upscale.name,
        'deband': deband,
        'denoise': denoise,
      };

  factory EnhanceSettings.fromJson(Map<String, Object?> json) =>
      EnhanceSettings(
        upscale: UpscalePreset.values.firstWhere(
          (p) => p.name == json['upscale'],
          orElse: () => UpscalePreset.off,
        ),
        deband: json['deband'] == true,
        denoise: json['denoise'] == true,
      );

  @override
  bool operator ==(Object other) =>
      other is EnhanceSettings &&
      other.upscale == upscale &&
      other.deband == deband &&
      other.denoise == denoise;

  @override
  int get hashCode => Object.hash(upscale, deband, denoise);
}
