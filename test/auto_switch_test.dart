import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/sources/reliability/auto_switch.dart';
import 'package:praxino/core/sources/source_adapter.dart';

PlayableStream _stream(String url) => PlayableStream(url);

void main() {
  test('switches on error and on a long enough stall', () {
    final auto = AutoSwitch(
      candidates: [_stream('a'), _stream('b'), _stream('c')],
      policy: FailoverPolicy(stallAfter: const Duration(seconds: 5)),
    );

    expect(auto.current!.url, 'a');
    expect(
      auto.trySwitch(stalledFor: const Duration(seconds: 4), hadError: false),
      isNull,
    );
    expect(
      auto.trySwitch(stalledFor: const Duration(seconds: 5), hadError: false)!
          .url,
      'b',
    );
    expect(
      auto.trySwitch(stalledFor: Duration.zero, hadError: true)!.url,
      'c',
    );
    expect(auto.trySwitch(stalledFor: Duration.zero, hadError: true), isNull);
  });

  test('honours maxAttempts', () {
    final policy = FailoverPolicy(maxAttempts: 1);
    final auto = AutoSwitch(
      candidates: [_stream('a'), _stream('b'), _stream('c')],
      policy: policy,
    );

    expect(auto.trySwitch(stalledFor: Duration.zero, hadError: true)!.url, 'b');
    expect(auto.trySwitch(stalledFor: Duration.zero, hadError: true), isNull);
    expect(policy.attempts, 1);
    expect(policy.exhausted, isTrue);
  });

  test('never returns to a failed candidate', () {
    final auto = AutoSwitch(
      candidates: [_stream('a'), _stream('b'), _stream('c')],
      policy: FailoverPolicy(maxAttempts: 5),
    );

    auto.trySwitch(stalledFor: Duration.zero, hadError: true); // a -> b
    auto.trySwitch(stalledFor: Duration.zero, hadError: true); // b -> c
    expect(auto.current!.url, 'c');
    expect(auto.hasNext, isFalse);
  });

  test('reset returns to the first candidate', () {
    final auto = AutoSwitch(
      candidates: [_stream('a'), _stream('b')],
      policy: FailoverPolicy(),
    );
    auto.trySwitch(stalledFor: Duration.zero, hadError: true);
    expect(auto.current!.url, 'b');

    auto.reset();
    expect(auto.current!.url, 'a');
    expect(auto.policy.attempts, 0);
    expect(auto.hasNext, isTrue);
  });
}
