import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/enhance/enhance_advisor.dart';
import 'package:praxino/core/enhance/enhance_settings.dart';

void main() {
  final start = DateTime(2026, 1, 1, 12);

  test('waits for a full window before judging', () {
    final advisor = EnhanceAdvisor();
    expect(
      advisor.evaluate(
        current: UpscalePreset.anime4kQuality,
        droppedFrames: 0,
        fps: 60,
        now: start,
      ),
      isNull,
    );
    expect(
      advisor.evaluate(
        current: UpscalePreset.anime4kQuality,
        droppedFrames: 100,
        fps: 60,
        now: start.add(const Duration(seconds: 2)),
      ),
      isNull,
    );
  });

  test('drops more than 5% of frames over the window', () {
    final advisor = EnhanceAdvisor();
    advisor.evaluate(
      current: UpscalePreset.anime4kQuality,
      droppedFrames: 0,
      fps: 60,
      now: start,
    );

    expect(
      advisor.evaluate(
        current: UpscalePreset.anime4kQuality,
        droppedFrames: 3,
        fps: 60,
        now: start.add(const Duration(seconds: 3)),
      ),
      isNull,
    );
    expect(
      advisor.evaluate(
        current: UpscalePreset.anime4kQuality,
        droppedFrames: 20,
        fps: 60,
        now: start.add(const Duration(seconds: 6)),
      ),
      UpscalePreset.anime4kBalanced,
    );
  });

  test('a manual choice suppresses suggestions for 30 minutes', () {
    final advisor = EnhanceAdvisor();
    advisor.evaluate(
      current: UpscalePreset.anime4kQuality,
      droppedFrames: 0,
      fps: 60,
      now: start,
    );
    advisor.noteUserChoice(start.add(const Duration(minutes: 1)));

    expect(
      advisor.evaluate(
        current: UpscalePreset.anime4kQuality,
        droppedFrames: 500,
        fps: 60,
        now: start.add(const Duration(minutes: 10)),
      ),
      isNull,
    );
    expect(advisor.hasUserOverride(start.add(const Duration(minutes: 31))),
        isFalse);
  });

  test('lower() walks quality -> balanced -> fast -> off', () {
    expect(EnhanceAdvisor.lower(UpscalePreset.anime4kQuality),
        UpscalePreset.anime4kBalanced);
    expect(EnhanceAdvisor.lower(UpscalePreset.anime4kBalanced),
        UpscalePreset.anime4kFast);
    expect(EnhanceAdvisor.lower(UpscalePreset.anime4kFast),
        UpscalePreset.off);
    expect(EnhanceAdvisor.lower(UpscalePreset.off), isNull);
  });
}
