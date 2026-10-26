/// When to resolve the next episode, and when to resolve it again.
///
/// Kept as pure thresholds so the player can decide without owning a timer.
class PrefetchSchedule {
  const PrefetchSchedule({
    this.startAfter = const Duration(seconds: 30),
    this.refreshBeforeEnd = const Duration(seconds: 90),
  });

  final Duration startAfter;
  final Duration refreshBeforeEnd;

  bool shouldStart(Duration position) => position >= startAfter;

  /// True while the current episode is close enough to the end that a cached
  /// stream URL may have expired and should be refreshed.
  bool shouldRefresh(Duration position, Duration duration) {
    if (duration <= Duration.zero) return false;
    final remaining = duration - position;
    return remaining > Duration.zero && remaining <= refreshBeforeEnd;
  }
}
