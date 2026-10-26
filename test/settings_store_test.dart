import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/library/watch_history.dart';
import 'package:praxino/core/settings/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('SettingsStore persists watch history', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await SettingsStore.load();
    final history = WatchHistory()
      ..record(WatchPoint(
        path: 'movie.mkv',
        position: const Duration(seconds: 42),
        duration: const Duration(minutes: 10),
        updatedAt: DateTime(2026, 1, 1),
      ));

    await store.saveWatchHistory(history);

    expect(store.watchHistory.find('movie.mkv')!.position,
        const Duration(seconds: 42));
  });
}
