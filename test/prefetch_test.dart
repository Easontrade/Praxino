import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/sources/reliability/prefetch.dart';

void main() {
  test('starts prefetching after 30 seconds by default', () {
    const schedule = PrefetchSchedule();
    expect(schedule.shouldStart(const Duration(seconds: 29)), isFalse);
    expect(schedule.shouldStart(const Duration(seconds: 30)), isTrue);
  });

  test('refreshes only near the end of a known duration', () {
    const schedule = PrefetchSchedule(refreshBeforeEnd: Duration(seconds: 90));
    const duration = Duration(minutes: 5);

    expect(schedule.shouldRefresh(const Duration(seconds: 209), duration),
        isFalse); // 91s left
    expect(schedule.shouldRefresh(const Duration(seconds: 210), duration),
        isTrue); // exactly 90s left
    expect(schedule.shouldRefresh(const Duration(seconds: 211), duration),
        isTrue); // 89s left
  });

  test('does not refresh without a duration or after the end', () {
    const schedule = PrefetchSchedule();
    expect(schedule.shouldRefresh(const Duration(seconds: 10), Duration.zero),
        isFalse);
    expect(
      schedule.shouldRefresh(const Duration(seconds: 310),
          const Duration(minutes: 5)),
      isFalse,
    );
  });
}
