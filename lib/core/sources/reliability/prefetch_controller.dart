import 'prefetch.dart';

/// Loads the next episode's stream after [PrefetchSchedule.startAfter] and
/// refreshes it near the end, without ever throwing into the player.
class PrefetchController<T> {
  PrefetchController({
    required this.load,
    this.schedule = const PrefetchSchedule(),
  });

  final Future<T> Function() load;
  final PrefetchSchedule schedule;

  int _loads = 0;
  bool _started = false;
  bool _loading = false;
  bool _refreshed = false;

  T? value;
  Object? error;

  int get loads => _loads;
  bool get isLoading => _loading;

  Future<void> onPosition(Duration position, Duration duration) async {
    if (_loading) return;
    if (!_started) {
      if (!schedule.shouldStart(position)) return;
      _started = true;
      await _run();
      return;
    }
    if (_refreshed) return;
    if (!schedule.shouldRefresh(position, duration)) return;
    _refreshed = true;
    await _run();
  }

  Future<void> _run() async {
    _loading = true;
    try {
      value = await load();
      error = null;
    } catch (failure) {
      error = failure;
    } finally {
      _loading = false;
      _loads++;
    }
  }
}
