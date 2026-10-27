import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/enhance/enhance_settings.dart';
import 'package:praxino/core/library/local_files.dart';

void main() {
  group('naturalCompare', () {
    test('orders episode numbers numerically', () {
      final files = ['EP10.mkv', 'EP2.mkv', 'EP1.mkv', 'ep03.mkv']
        ..sort(naturalCompare);
      expect(files, ['EP1.mkv', 'EP2.mkv', 'ep03.mkv', 'EP10.mkv']);
    });
  });

  group('EnhanceSettings', () {
    test('off clears shaders and filters', () {
      final props = const EnhanceSettings()
          .toMpvProperties(shaderDir: '/s', listSeparator: ';');
      expect(props['glsl-shaders'], '');
      expect(props['vf'], '');
      expect(props['deband'], 'no');
      expect(props['hwdec'], 'auto-safe');
    });

    test('presets join shader paths in hook order', () {
      final props = const EnhanceSettings(upscale: UpscalePreset.anime4kQuality)
          .toMpvProperties(shaderDir: '/s', listSeparator: ';');
      final shaders = props['glsl-shaders']!.split(';');
      expect(shaders.first, '/s/Anime4K_Clamp_Highlights.glsl');
      expect(shaders, contains('/s/Anime4K_Upscale_CNN_x2_VL.glsl'));
      expect(shaders.length, 6);
    });

    test('fsrcnnx preset has its own family and shader', () {
      final props = const EnhanceSettings(upscale: UpscalePreset.fsrcnnx)
          .toMpvProperties(shaderDir: '/s', listSeparator: ';');
      expect(props['glsl-shaders'], '/s/FSRCNNX_x2_16-0-4-1.glsl');
      expect(UpscalePreset.fsrcnnx.shaderFamily, 'fsrcnnx');
      expect(UpscalePreset.anime4kFast.shaderFamily, 'anime4k');
    });

    test('denoise adds the GPU shader and keeps GPU decoding', () {
      final props = const EnhanceSettings(denoise: true).toMpvProperties(
        shaderDir: '/s',
        listSeparator: ';',
        denoiseShader: '/s/denoise.glsl',
      );
      expect(props['glsl-shaders'], '/s/denoise.glsl');
      expect(props['vf'], '');
      expect(props['hwdec'], 'auto-safe');
    });

    test('round-trips through json', () {
      const s = EnhanceSettings(
          upscale: UpscalePreset.anime4kBalanced, deband: true);
      expect(EnhanceSettings.fromJson(s.toJson()), s);
    });
  });
}
