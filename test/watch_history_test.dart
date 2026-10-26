import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/library/watch_history.dart';

WatchPoint _point(
  String path,
  int positionSeconds,
  int durationSeconds, {
  DateTime? updatedAt,
}) =>
    WatchPoint(
      path: path,
      position: Duration(seconds: positionSeconds),
      duration: Duration(seconds: durationSeconds),
      updatedAt: updatedAt ?? DateTime(2026, 1, 1),
    );

void main() {
  group('WatchPoint.shouldResume', () {
    test('requires more than 10s played and more than 30s left', () {
      expect(_point('a.mkv', 5, 600).shouldResume, isFalse);
      expect(_point('a.mkv', 10, 600).shouldResume, isFalse);
      expect(_point('a.mkv', 11, 600).shouldResume, isTrue);
    });

    test('does not resume near the end', () {
      expect(_point('a.mkv', 570, 600).shouldResume, isFalse);
      expect(_point('a.mkv', 569, 600).shouldResume, isTrue);
      expect(_point('a.mkv', 600, 600).shouldResume, isFalse);
    });
  });

  test('record replaces the same path and keeps the newest point', () {
    final history = WatchHistory()
      ..record(_point('a.mkv', 10, 600, updatedAt: DateTime(2026, 1, 1)))
      ..record(_point('a.mkv', 20, 600, updatedAt: DateTime(2026, 1, 2)));

    expect(history.length, 1);
    expect(history.find('a.mkv')!.position, const Duration(seconds: 20));
  });

  test('trims the oldest entries when over maxEntries', () {
    final history = WatchHistory(maxEntries: 2);
    for (var i = 0; i < 3; i++) {
      history.record(_point('$i.mkv', 10, 600,
          updatedAt: DateTime(2026, 1, i + 1)));
    }

    expect(history.length, 2);
    expect(history.find('0.mkv'), isNull);
    expect(history.find('1.mkv'), isNotNull);
    expect(history.find('2.mkv'), isNotNull);
  });

  test('entries are most recently watched first', () {
    final history = WatchHistory()
      ..record(_point('old.mkv', 10, 600, updatedAt: DateTime(2026, 1, 1)))
      ..record(_point('new.mkv', 10, 600, updatedAt: DateTime(2026, 1, 3)))
      ..record(_point('mid.mkv', 10, 600, updatedAt: DateTime(2026, 1, 2)));

    expect(history.entries.map((e) => e.path), ['new.mkv', 'mid.mkv', 'old.mkv']);
  });

  test('json round-trips and skips invalid entries', () {
    final history = WatchHistory()..record(_point('a.mkv', 42, 600));
    final decoded = WatchHistory.fromJson(history.toJson());

    expect(decoded.find('a.mkv')!.position, const Duration(seconds: 42));

    final broken = WatchHistory.fromJson('[{"path":"x"}, null, 3]');
    expect(broken.length, 0);
    expect(WatchHistory.fromJson(null).length, 0);
    expect(WatchHistory.fromJson('not json').length, 0);
  });
}
