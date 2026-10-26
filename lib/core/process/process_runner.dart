import 'dart:io';

/// Captured output of one child process.
class ProcessOutput {
  const ProcessOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Runs external tools (yt-dlp today). Injected so adapters are testable.
abstract interface class ProcessRunner {
  Future<ProcessOutput> run(String executable, List<String> arguments);
}

class SystemProcessRunner implements ProcessRunner {
  const SystemProcessRunner();

  @override
  Future<ProcessOutput> run(String executable, List<String> arguments) async {
    final result = await Process.run(
      executable,
      arguments,
      runInShell: false,
    );
    return ProcessOutput(
      exitCode: result.exitCode,
      stdout: '${result.stdout}',
      stderr: '${result.stderr}',
    );
  }
}
