import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/enhance/compare_state.dart';
import 'package:praxino/core/enhance/enhance_settings.dart';

void main() {
  const quality = EnhanceSettings(
    upscale: UpscalePreset.anime4kQuality,
    deband: true,
    denoise: true,
  );

  test('begin disables everything and end restores it', () {
    final state = CompareState();
    expect(state.active, isFalse);

    expect(state.begin(quality), const EnhanceSettings());
    expect(state.active, isTrue);
    expect(state.end(), quality);
    expect(state.active, isFalse);
  });

  test('a second begin is ignored', () {
    final state = CompareState()..begin(quality);
    expect(state.begin(quality), isNull);
  });

  test('changes while comparing update the restore value', () {
    const changed = EnhanceSettings(upscale: UpscalePreset.anime4kFast);
    final state = CompareState()..begin(quality);
    state.noteSettingsChange(changed);
    expect(state.end(), changed);
  });
}
