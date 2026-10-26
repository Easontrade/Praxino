import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/sources/reliability/prefetch_controller.dart';

void main() {
  test('loads once after 30 seconds', () async {
    var calls = 0;
    final controller = PrefetchController<String>(
      load: () async {
        calls++;
        return 'next';
      },
    );

    await controller.onPosition(const Duration(seconds: 29), Duration.zero);
    expect(calls, 0);

    await controller.onPosition(const Duration(seconds: 30), Duration.zero);
    expect(calls, 1);
    expect(controller.value, 'next');

    await controller.onPosition(const Duration(seconds: 40), Duration.zero);
    expect(calls, 1);
  });

  test('refreshes once near the end', () async {
    var calls = 0;
    final controller = PrefetchController<String>(
      load: () async => 'next-${++calls}',
    );

    await controller.onPosition(const Duration(seconds: 30), const Duration(minutes: 5));
    expect(controller.value, 'next-1');

    await controller.onPosition(const Duration(seconds: 209), const Duration(minutes: 5));
    expect(calls, 1);

    await controller.onPosition(const Duration(seconds: 210), const Duration(minutes: 5));
    expect(calls, 2);
    expect(controller.value, 'next-2');

    await controller.onPosition(const Duration(seconds: 211), const Duration(minutes: 5));
    expect(calls, 2);
  });

  test('keeps the error instead of throwing', () async {
    final controller = PrefetchController<String>(
      load: () async => throw StateError('boom'),
    );

    await controller.onPosition(const Duration(seconds: 30), Duration.zero);
    expect(controller.error, isA<StateError>());
    expect(controller.value, isNull);
  });
}
