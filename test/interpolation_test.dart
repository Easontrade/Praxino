import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/enhance/enhance_settings.dart';
import 'package:praxino/core/enhance/interpolation.dart';

void main() {
  test('composes denoise before vapoursynth in one vf chain', () {
    final vf = buildVideoFilterChain(
      denoise: true,
      interpolation: InterpolationMode.rife,
      vapoursynthScript: 'C:/Praxino/cache/rife.vpy',
    );
    expect(
      vf,
      'lavfi=[hqdn3d=1.2:1.0:6:6],vapoursynth=C:/Praxino/cache/rife.vpy',
    );
  });

  test('interpolation without a script contributes nothing', () {
    expect(
      buildVideoFilterChain(
        denoise: false,
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
    );
    expect(props['vf'], contains('hqdn3d'));
    expect(props['vf'], contains('vapoursynth=/cache/mvtools.vpy'));
    expect(props['hwdec'], 'auto-copy');
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
