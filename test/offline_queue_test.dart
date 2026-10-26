import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/enhance/offline/ffmpeg_runner.dart';
import 'package:praxino/core/enhance/offline/offline_job.dart';
import 'package:praxino/core/enhance/offline/offline_queue.dart';

class _FakeProcessor implements OfflineProcessor {
  _FakeProcessor({this.slowIds = const {}, this.failFirst = false});

  final Set<String> slowIds;
  final bool failFirst;
  final List<String> started = [];
  final Map<String, int> attempts = {};
  Completer<void>? slowStarted;

  @override
  Future<void> run(
    OfflineJob job, {
    required void Function(double progress) onProgress,
    required bool Function() stop,
  }) async {
    started.add(job.id);
    attempts[job.id] = (attempts[job.id] ?? 0) + 1;
    if (failFirst && attempts[job.id] == 1) {
      throw const OfflineException('boom');
    }
    onProgress(0.4);
    if (slowIds.contains(job.id) && attempts[job.id] == 1) {
      slowStarted ??= Completer<void>();
      if (!slowStarted!.isCompleted) slowStarted!.complete();
      while (!stop()) {
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
    }
    onProgress(1);
  }
}

OfflineJob _job(String id) => OfflineJob(
      id: id,
      sourcePath: 'C:/videos/$id.mkv',
      outputPath: 'C:/videos/${id}_enhanced.mp4',
      createdAt: DateTime(2026),
    );

void main() {
  test('runs queued jobs sequentially to completion', () async {
    final processor = _FakeProcessor();
    final queue = OfflineQueue(processor: processor);
    queue.add(_job('a'));
    queue.add(_job('b'));

    await queue.start();

    expect(queue.jobs.map((job) => job.status),
        everyElement(OfflineJobStatus.completed));
    expect(processor.started, ['a', 'b']);
    expect(queue.jobs.first.progress, 1);
  });

  test('pauses and resumes a running job', () async {
    final processor = _FakeProcessor(slowIds: {'slow'});
    final queue = OfflineQueue(processor: processor);
    queue.add(_job('slow'));

    final running = queue.start();
    await processor.slowStarted!.future;
    queue.pause('slow');
    await running;
    expect(queue.jobs.single.status, OfflineJobStatus.paused);

    queue.resume('slow');
    expect(queue.jobs.single.status, OfflineJobStatus.queued);
    await queue.start();
    expect(queue.jobs.single.status, OfflineJobStatus.completed);
  });

  test('cancels and retries a failed job', () async {
    final processor = _FakeProcessor(failFirst: true);
    final queue = OfflineQueue(processor: processor);
    queue.add(_job('bad'));

    await queue.start();
    expect(queue.jobs.single.status, OfflineJobStatus.failed);
    expect(queue.jobs.single.error, contains('boom'));

    queue.retry('bad');
    await queue.start();
    expect(queue.jobs.single.status, OfflineJobStatus.completed);
  });

  test('persists every state transition', () async {
    final snapshots = <List<OfflineJob>>[];
    final queue = OfflineQueue(
      processor: _FakeProcessor(),
      persist: (jobs) async => snapshots.add(jobs),
    );
    queue.add(_job('a'));
    await queue.start();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(snapshots, isNotEmpty);
    expect(snapshots.last.single.status, OfflineJobStatus.completed);
  });

  test('parses ffmpeg time lines', () {
    expect(
      FfmpegProgress.parseTime('frame=1 time=00:01:02.50 bitrate=1'),
      const Duration(minutes: 1, seconds: 2, milliseconds: 500),
    );
    expect(
      FfmpegProgress.fraction(
        'time=00:00:30.00',
        const Duration(minutes: 1),
      ),
      0.5,
    );
    expect(FfmpegProgress.parseTime('no time here'), isNull);
  });
}
