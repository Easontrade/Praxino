import 'package:path/path.dart' as p;

enum OfflineJobStatus { queued, running, paused, completed, failed, cancelled }

class OfflineJob {
  const OfflineJob({
    required this.id,
    required this.sourcePath,
    required this.outputPath,
    this.status = OfflineJobStatus.queued,
    this.progress = 0,
    this.error,
    required this.createdAt,
  });

  final String id;
  final String sourcePath;
  final String outputPath;
  final OfflineJobStatus status;
  final double progress;
  final String? error;
  final DateTime createdAt;

  factory OfflineJob.forSource(String sourcePath, {String? id, DateTime? now}) {
    final stamp = now ?? DateTime.now();
    return OfflineJob(
      id: id ?? '${stamp.microsecondsSinceEpoch}',
      sourcePath: sourcePath,
      outputPath: p.join(
        p.dirname(sourcePath),
        '${p.basenameWithoutExtension(sourcePath)}_enhanced.mp4',
      ),
      createdAt: stamp,
    );
  }

  OfflineJob copyWith({
    OfflineJobStatus? status,
    double? progress,
    String? error,
    bool clearError = false,
  }) =>
      OfflineJob(
        id: id,
        sourcePath: sourcePath,
        outputPath: outputPath,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        error: clearError ? null : error ?? this.error,
        createdAt: createdAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'source': sourcePath,
        'output': outputPath,
        'status': status.name,
        'progress': progress,
        'error': error,
        'createdAt': createdAt.toIso8601String(),
      };

  static OfflineJob? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final source = raw['source'];
    final output = raw['output'];
    if (id is! String || source is! String || output is! String) return null;
    final status = OfflineJobStatus.values
        .where((value) => value.name == raw['status'])
        .firstOrNull;
    return OfflineJob(
      id: id,
      sourcePath: source,
      outputPath: output,
      status: status ?? OfflineJobStatus.queued,
      progress: raw['progress'] is num ? (raw['progress'] as num).toDouble() : 0,
      error: raw['error'] is String ? raw['error'] as String : null,
      createdAt: DateTime.tryParse('${raw['createdAt'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

abstract interface class OfflineProcessor {
  Future<void> run(
    OfflineJob job, {
    required void Function(double progress) onProgress,
    required bool Function() stop,
  });
}

class OfflineException implements Exception {
  const OfflineException(this.message);

  final String message;

  @override
  String toString() => message;
}
