import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/enhance/enhance_settings.dart';
import 'package:praxino/core/enhance/interpolation.dart';

void main() {
  test('composes the vapoursynth filter', () {
    final vf = buildVideoFilterChain(
      interpolation: InterpolationMode.rife,
      vapoursynthScript: 'C:/Praxino/cache/rife.vpy',
    );
    expect(vf, 'vapoursynth=C:/Praxino/cache/rife.vpy');
  });

  test('denoise no longer writes a lavfi filter', () {
    final props = const EnhanceSettings(denoise: true).toMpvProperties(
      shaderDir: '/s',
      listSeparator: ';',
      denoiseShader: '/s/denoise.glsl',
    );
    expect(props['vf'], '');
    expect(props['glsl-shaders'], '/s/denoise.glsl');
  });

  test('interpolation without a script contributes nothing', () {
    expect(
      buildVideoFilterChain(
        interpolation: InterpolationMode.rife,
      ),
      '',
    );
  });

  test('settings reflect the combined chain and copy-back decoding', () {
    const settings = EnhanceSettings(
      denoise: true,
      interpolation: InterpolationMode.mvtools,
    );
    final props = settings.toMpvProperties(
      shaderDir: '/s',
      listSeparator: ';',
      vapoursynthScript: '/cache/mvtools.vpy',
      denoiseShader: '/s/denoise.glsl',
    );
    expect(props['vf'], 'vapoursynth=/cache/mvtools.vpy');
    expect(props['glsl-shaders'], startsWith('/s/denoise.glsl'));
    expect(props['hwdec'], 'auto-copy');
    expect(props['video-sync'], 'display-resample');
    expect(props['audio-pitch-correction'], 'yes');
  });

  test('each mode uses its bundled template unless overridden', () {
    expect(
      interpolationScriptFor(InterpolationMode.off, templateDir: '/t'),
      isNull,
    );
    expect(
      interpolationScriptFor(InterpolationMode.mvtools, templateDir: '/t'),
      endsWith('mvtools_flowfps.vpy'),
    );
    expect(
      interpolationScriptFor(InterpolationMode.rife, templateDir: '/t'),
      endsWith('rife_ncnn.vpy'),
    );
    expect(
      interpolationScriptFor(
        InterpolationMode.rife,
        templateDir: '/t',
        profile: RifeProfile.fixed60,
      ),
      endsWith('rife_ncnn_60.vpy'),
    );
    expect(
      interpolationScriptFor(InterpolationMode.rife,
          templateDir: '/t', override: ' /mine.vpy '),
      '/mine.vpy',
    );
    expect(
      interpolationScriptFor(InterpolationMode.off,
          templateDir: '/t', override: '/mine.vpy'),
      isNull,
    );
  });

  test('interpolation mode round-trips through json', () {
    const settings = EnhanceSettings(
      interpolation: InterpolationMode.rife,
      rifeProfile: RifeProfile.fixed60,
    );
    expect(EnhanceSettings.fromJson(settings.toJson()), settings);
  });
}
