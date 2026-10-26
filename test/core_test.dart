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

    test('denoise switches to copy-back decoding', () {
      final props = const EnhanceSettings(denoise: true)
          .toMpvProperties(shaderDir: '/s', listSeparator: ';');
      expect(props['hwdec'], 'auto-copy');
      expect(props['vf'], startsWith('lavfi='));
    });

    test('round-trips through json', () {
      const s = EnhanceSettings(
          upscale: UpscalePreset.anime4kBalanced, deband: true);
      expect(EnhanceSettings.fromJson(s.toJson()), s);
    });
  });
}
