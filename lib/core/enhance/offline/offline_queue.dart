import 'dart:async';

import 'offline_job.dart';

/// Sequential offline job queue with pause/resume/cancel and retry.
class OfflineQueue {
  OfflineQueue({
    required this.processor,
    List<OfflineJob> initial = const [],
    this.persist,
  }) : _jobs = List.of(initial);

  final OfflineProcessor processor;
  final Future<void> Function(List<OfflineJob> jobs)? persist;

  final List<OfflineJob> _jobs;
  final Set<String> _stop = {};
  final Set<String> _pausedRequests = {};
  bool _running = false;

  List<OfflineJob> get jobs => List.unmodifiable(_jobs);

  bool get isRunning => _running;

  void add(OfflineJob job) {
    _jobs.add(job);
    _save();
  }

  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final next = _jobs.where((job) => job.status == OfflineJobStatus.queued).firstOrNull;
        if (next == null) break;
        _replace(next.copyWith(
          status: OfflineJobStatus.running,
          progress: 0,
          clearError: true,
        ));
        try {
          await processor.run(
            next,
            onProgress: (progress) {
              final current = _find(next.id);
              if (current != null && current.status == OfflineJobStatus.running) {
                _replace(current.copyWith(progress: progress.clamp(0, 1)));
              }
            },
            stop: () => _stop.contains(next.id),
          );
          final request = _stop.remove(next.id) ? 'stop' : null;
          final current = _find(next.id);
          if (current == null) continue;
          if (request != null) {
            _replace(current.copyWith(
              status: _pausedRequests.remove(next.id)
                  ? OfflineJobStatus.paused
                  : OfflineJobStatus.cancelled,
            ));
          } else {
            _replace(current.copyWith(
              status: OfflineJobStatus.completed,
              progress: 1,
              clearError: true,
            ));
          }
        } catch (error) {
          final current = _find(next.id);
          if (current != null) {
            _replace(current.copyWith(
              status: OfflineJobStatus.failed,
              error: '$error',
            ));
          }
        }
      }
    } finally {
      _running = false;
    }
  }

  void pause(String id) {
    final job = _find(id);
    if (job == null) return;
    if (job.status == OfflineJobStatus.queued) {
      _replace(job.copyWith(status: OfflineJobStatus.paused));
    } else if (job.status == OfflineJobStatus.running) {
      _pausedRequests.add(id);
      _stop.add(id);
    }
  }

  void resume(String id) {
    final job = _find(id);
    if (job == null || job.status != OfflineJobStatus.paused) return;
    _replace(job.copyWith(status: OfflineJobStatus.queued));
  }

  void cancel(String id) {
    final job = _find(id);
    if (job == null) return;
    if (job.status == OfflineJobStatus.running) {
      _stop.add(id);
    } else if (job.status != OfflineJobStatus.completed) {
      _replace(job.copyWith(status: OfflineJobStatus.cancelled));
    }
  }

  void retry(String id) {
    final job = _find(id);
    if (job == null) return;
    if (job.status != OfflineJobStatus.failed &&
        job.status != OfflineJobStatus.cancelled) {
      return;
    }
    _replace(job.copyWith(
      status: OfflineJobStatus.queued,
      progress: 0,
      clearError: true,
    ));
  }

  void remove(String id) {
    _jobs.removeWhere((job) => job.id == id);
    _save();
  }

  OfflineJob? _find(String id) {
    for (final job in _jobs) {
      if (job.id == id) return job;
    }
    return null;
  }

  void _replace(OfflineJob job) {
    final index = _jobs.indexWhere((candidate) => candidate.id == job.id);
    if (index < 0) return;
    _jobs[index] = job;
    _save();
  }

  void _save() {
    final callback = persist;
    if (callback != null) unawaited(callback(List.unmodifiable(_jobs)));
  }
}
