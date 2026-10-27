import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/process/process_runner.dart';
import 'package:praxino/core/subtitles/ai/transcriber.dart';

class _FakeRunner implements ProcessRunner {
  _FakeRunner(this.output);

  final ProcessOutput output;
  final List<(String, List<String>)> calls = [];

  @override
  Future<ProcessOutput> run(String executable, List<String> arguments) async {
    calls.add((executable, arguments));
    return output;
  }
}

const _whisperCppJson = '''
{
  "systeminfo": "whisper.cpp",
  "result": {"language": "en"},
  "transcription": [
    {
      "timestamps": {"from": "00:00:00,000", "to": "00:00:02,500"},
      "offsets": {"from": 0, "to": 2500},
      "text": " Hello there"
    },
    {
      "timestamps": {"from": "00:00:02,500", "to": "00:00:05,000"},
      "offsets": {"from": 2500, "to": 5000},
      "text": " Second line"
    }
  ]
}
''';

const _fasterWhisperJson = '''
{
  "language": "en",
  "segments": [
    {"id": 0, "start": 0.0, "end": 2.5, "text": " Hi"},
    {"id": 1, "start": 2.5, "end": 5.0, "text": " there"}
  ]
}
''';

const _output = ProcessOutput(exitCode: 0, stdout: '', stderr: '');

void main() {
  test('runs whisper.cpp with an argument list and parses its JSON', () async {
    final runner = _FakeRunner(_output);
    final transcriber = WhisperCliTranscriber(
      executable: r'C:\Tools\whisper\whisper-cli.exe',
      model: r'C:\Tools\whisper\ggml-large-v3-turbo.bin',
      runner: runner,
      readTextFile: (path) async =>
          path.endsWith('transcript.json') ? _whisperCppJson : null,
    );

    final segments = await transcriber.transcribe(
      r'C:\Temp\audio.wav',
      language: 'en',
    );

    expect(segments, hasLength(2));
    expect(segments[0].id, 1);
    expect(segments[0].start, Duration.zero);
    expect(segments[0].end, const Duration(milliseconds: 2500));
    expect(segments[0].text, 'Hello there');
    expect(segments[1].id, 2);
    expect(segments[1].start, const Duration(milliseconds: 2500));
    expect(segments[1].text, 'Second line');

    final (executable, arguments) = runner.calls.single;
    expect(executable, r'C:\Tools\whisper\whisper-cli.exe');
    expect(
      arguments,
      containsAllInOrder([
        '-m',
        r'C:\Tools\whisper\ggml-large-v3-turbo.bin',
        '-f',
        r'C:\Temp\audio.wav',
      ]),
    );
    expect(arguments, contains('-oj'));
    expect(arguments[arguments.indexOf('-l') + 1], 'en');
  });

  test('whisper.cpp defaults to auto language detection', () async {
    final runner = _FakeRunner(
      const ProcessOutput(exitCode: 0, stdout: _whisperCppJson, stderr: ''),
    );
    final transcriber = WhisperCliTranscriber(
      executable: 'whisper-cli',
      model: 'model.bin',
      runner: runner,
    );

    final segments = await transcriber.transcribe('audio.wav');

    expect(segments, hasLength(2));
    final arguments = runner.calls.single.$2;
    expect(arguments[arguments.indexOf('-l') + 1], 'auto');
  });

  test('parses faster-whisper JSON with seconds and its CLI arguments',
      () async {
    final runner = _FakeRunner(
      const ProcessOutput(exitCode: 0, stdout: _fasterWhisperJson, stderr: ''),
    );
    final transcriber = WhisperCliTranscriber(
      executable: 'faster-whisper.exe',
      model: 'large-v3',
      flavor: WhisperFlavor.fasterWhisper,
      runner: runner,
    );

    final segments = await transcriber.transcribe(
      r'C:\Temp\audio.wav',
      language: 'en',
    );

    expect(segments, hasLength(2));
    expect(segments[0].id, 0);
    expect(segments[0].start, Duration.zero);
    expect(segments[0].end, const Duration(milliseconds: 2500));
    expect(segments[1].end, const Duration(seconds: 5));

    final arguments = runner.calls.single.$2;
    expect(arguments.first, r'C:\Temp\audio.wav');
    expect(
      arguments,
      containsAllInOrder(['--model', 'large-v3']),
    );
    expect(arguments, containsAllInOrder(['--output_format', 'json']));
    expect(arguments, contains('--output_dir'));
    expect(arguments, containsAllInOrder(['--language', 'en']));
  });

  test('faster-whisper omits --language when it is not set', () async {
    final runner = _FakeRunner(
      const ProcessOutput(exitCode: 0, stdout: _fasterWhisperJson, stderr: ''),
    );
    final transcriber = WhisperCliTranscriber(
      executable: 'faster-whisper.exe',
      model: 'large-v3',
      flavor: WhisperFlavor.fasterWhisper,
      runner: runner,
    );

    await transcriber.transcribe('audio.wav');

    expect(runner.calls.single.$2, isNot(contains('--language')));
  });

  test('reads the JSON file when the tool prints nothing', () async {
    final runner = _FakeRunner(_output);
    final requested = <String>[];
    final transcriber = WhisperCliTranscriber(
      executable: 'faster-whisper.exe',
      model: 'large-v3',
      flavor: WhisperFlavor.fasterWhisper,
      runner: runner,
      readTextFile: (path) async {
        requested.add(path);
        return _fasterWhisperJson;
      },
    );

    final segments = await transcriber.transcribe(r'C:\Temp\audio.wav');

    expect(segments, hasLength(2));
    expect(requested.single, endsWith('audio.json'));
  });

  test('tolerates a bare array and treats whisper.cpp numbers as ms', () {
    final segments = parseWhisperJson(
      '[{"start": 1000, "end": 2000, "text": "A"}]',
    );
    expect(segments.single.start, const Duration(seconds: 1));
    expect(segments.single.end, const Duration(seconds: 2));
    expect(segments.single.id, 1);
  });

  test('treats faster-whisper numbers as seconds', () {
    final segments = parseWhisperJson(
      '[{"start": 1.5, "end": 2.25, "text": "B"}]',
      flavor: WhisperFlavor.fasterWhisper,
    );
    expect(segments.single.start, const Duration(milliseconds: 1500));
    expect(segments.single.end, const Duration(milliseconds: 2250));
  });

  test('skips entries without text or timing', () {
    final segments = parseWhisperJson(
      '{"segments": ['
      '{"id": 1, "start": 0, "end": 1000, "text": "  "},'
      '{"id": 2, "start": 0, "end": 1000, "text": "kept"},'
      '{"id": 3, "start": 0, "text": "no end"}'
      ']}',
    );
    expect(segments, hasLength(1));
    expect(segments.single.id, 2);
    expect(segments.single.text, 'kept');
  });

  test('reports a non-zero exit code and unusable output', () async {
    final failing = WhisperCliTranscriber(
      executable: 'whisper-cli',
      model: 'model.bin',
      runner: _FakeRunner(
        const ProcessOutput(exitCode: 2, stdout: '', stderr: 'boom'),
      ),
    );
    await expectLater(
      failing.transcribe('audio.wav'),
      throwsA(isA<TranscriptionException>().having(
        (error) => error.message,
        'message',
        contains('退出码 2'),
      )),
    );

    final empty = WhisperCliTranscriber(
      executable: 'whisper-cli',
      model: 'model.bin',
      runner: _FakeRunner(_output),
      readTextFile: (path) async => null,
    );
    await expectLater(
      empty.transcribe('audio.wav'),
      throwsA(isA<TranscriptionException>().having(
        (error) => error.message,
        'message',
        contains('JSON'),
      )),
    );
  });

  test('refuses to run without an executable or a model', () async {
    final runner = _FakeRunner(_output);
    await expectLater(
      WhisperCliTranscriber(executable: '', model: 'm', runner: runner)
          .transcribe('audio.wav'),
      throwsA(isA<TranscriptionException>()),
    );
    await expectLater(
      WhisperCliTranscriber(executable: 'w', model: '', runner: runner)
          .transcribe('audio.wav'),
      throwsA(isA<TranscriptionException>()),
    );
    expect(runner.calls, isEmpty);
  });
}
