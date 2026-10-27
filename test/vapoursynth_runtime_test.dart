import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/enhance/vapoursynth_runtime.dart';

void main() {
  test('builds the environment for a portable install', () {
    const runtime = VapourSynthRuntime(
      pythonDir: r'C:\py',
      siteDir: r'C:\py\Lib\site-packages\vapoursynth',
    );
    final env = runtime.environment(r'C:\Windows');

    expect(env['PATH'],
        r'C:\py;C:\py\Lib\site-packages\vapoursynth;C:\Windows');
    expect(env['PYTHONPATH'], r'C:\py\Lib\site-packages');
    expect(env['VAPOURSYNTH_PLUGIN_PATH'],
        r'C:\py\Lib\site-packages\vapoursynth\plugins');
  });

  test('is not configured until both directories are set', () {
    expect(const VapourSynthRuntime(pythonDir: '', siteDir: '').isConfigured,
        isFalse);
    expect(
        const VapourSynthRuntime(pythonDir: r'C:\py', siteDir: '').isConfigured,
        isFalse);
  });
}
