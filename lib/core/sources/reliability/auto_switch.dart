import '../source_adapter.dart';

/// When to give up on the current stream and try the next candidate.
class FailoverPolicy {
  FailoverPolicy({
    this.stallAfter = const Duration(seconds: 8),
    this.maxAttempts = 3,
  });

  /// How long playback may make no progress before switching.
  final Duration stallAfter;

  /// Hard cap on switches for one playback session.
  final int maxAttempts;

  int _attempts = 0;

  int get attempts => _attempts;
  bool get exhausted => _attempts >= maxAttempts;

  bool shouldSwitch({
    required Duration stalledFor,
    required bool hadError,
  }) {
    if (exhausted) return false;
    if (hadError) return true;
    return stalledFor >= stallAfter;
  }

  void recordSwitch() => _attempts++;

  void reset() => _attempts = 0;
}

/// Walks the candidate streams, never revisiting one that already failed.
class AutoSwitch {
  AutoSwitch({
    required Iterable<PlayableStream> candidates,
    FailoverPolicy? policy,
  })  : _candidates = List.unmodifiable(candidates),
        policy = policy ?? FailoverPolicy();

  final List<PlayableStream> _candidates;
  final FailoverPolicy policy;
  final Set<String> _failed = {};
  int _index = 0;

  List<PlayableStream> get candidates => _candidates;

  PlayableStream? get current =>
      _candidates.isEmpty ? null : _candidates[_index];

  bool get hasNext => _nextIndex() != null;

  /// Switches when [policy] allows it; returns the new stream or null when
  /// there is nothing left to try.
  PlayableStream? trySwitch({
    required Duration stalledFor,
    required bool hadError,
  }) {
    if (!policy.shouldSwitch(stalledFor: stalledFor, hadError: hadError)) {
      return null;
    }
    final next = _nextIndex();
    if (next == null) return null;
    final currentUrl = current?.url;
    if (currentUrl != null) _failed.add(currentUrl);
    _index = next;
    policy.recordSwitch();
    return current;
  }

  int? _nextIndex() {
    for (var i = _index + 1; i < _candidates.length; i++) {
      if (!_failed.contains(_candidates[i].url)) return i;
    }
    for (var i = 0; i < _index; i++) {
      if (!_failed.contains(_candidates[i].url)) return i;
    }
    return null;
  }

  void reset() {
    _failed.clear();
    _index = 0;
    policy.reset();
  }
}
