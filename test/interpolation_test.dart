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

  test('interpolation mode round-trips through json', () {
    const settings = EnhanceSettings(interpolation: InterpolationMode.rife);
    expect(EnhanceSettings.fromJson(settings.toJson()), settings);
  });
}
