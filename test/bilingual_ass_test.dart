import 'package:flutter_test/flutter_test.dart';
import 'package:praxino/core/subtitles/ai/bilingual_ass.dart';
import 'package:praxino/core/subtitles/ai/transcript.dart';

const _segments = [
  TranscriptSegment(
    id: 1,
    start: Duration(seconds: 1),
    end: Duration(seconds: 2, milliseconds: 500),
    text: 'Hello, world',
  ),
  TranscriptSegment(
    id: 2,
    start: Duration(minutes: 1, seconds: 2, milliseconds: 5),
    end: Duration(minutes: 1, seconds: 4),
    text: 'Second line',
  ),
];

/// The ASS text field is everything after the ninth comma; commas inside it do
/// not need (and must not get) escaping.
String _dialogueText(String line) => line.split(',').skip(9).join(',');

List<String> _dialogues(String ass) =>
    ass.split('\n').where((line) => line.startsWith('Dialogue:')).toList();

String _style(String ass, String prefix) =>
    ass.split('\n').firstWhere((line) => line.startsWith('Style: $prefix'));

int _fontSize(String styleLine) => int.parse(styleLine.split(',')[2]);

int _marginV(String styleLine) => int.parse(styleLine.split(',')[21]);

int _alignment(String styleLine) => int.parse(styleLine.split(',')[18]);

void main() {
  test('formats ASS timestamps as H:MM:SS.cc', () {
    expect(formatAssTime(Duration.zero), '0:00:00.00');
    expect(formatAssTime(const Duration(seconds: 1)), '0:00:01.00');
    expect(
      formatAssTime(const Duration(minutes: 1, seconds: 2, milliseconds: 500)),
      '0:01:02.50',
    );
    expect(
      formatAssTime(
        const Duration(hours: 10, minutes: 5, seconds: 7, milliseconds: 99),
      ),
      '10:05:07.09',
    );
    // Sub-centisecond characters are truncated, not rounded.
    expect(formatAssTime(const Duration(milliseconds: 1999)), '0:00:01.99');
    expect(formatAssTime(const Duration(milliseconds: -5)), '0:00:00.00');
  });

  test('formats SRT timestamps as HH:MM:SS,mmm', () {
    expect(formatSrtTime(Duration.zero), '00:00:00,000');
    expect(
      formatSrtTime(const Duration(minutes: 1, seconds: 2, milliseconds: 5)),
      '00:01:02,005',
    );
    expect(
      formatSrtTime(const Duration(hours: 2, seconds: 3, milliseconds: 40)),
      '02:00:03,040',
    );
  });

  test('escapes braces, backslashes and line breaks for libass', () {
    expect(escapeAssText(r'a\b'), r'a\\b');
    expect(escapeAssText('{note}'), r'\{note\}');
    expect(escapeAssText('line1\r\nline2'), r'line1\Nline2');
    expect(escapeAssText('line1\nline2'), r'line1\Nline2');
    expect(escapeAssText('a\rb'), r'a\Nb');
    expect(escapeAssText('plain text'), 'plain text');
  });

  test('keeps commas inside the dialogue text field', () {
    final ass = buildBilingualAss(
      segments: const [
        TranscriptSegment(
          id: 7,
          start: Duration.zero,
          end: Duration(seconds: 2),
          text: 'one, two, three',
        ),
      ],
      translations: const {7: '一，二，三'},
    );
    final dialogues = _dialogues(ass);
    expect(dialogues, hasLength(2));
    expect(_dialogueText(dialogues[0]), '一，二，三');
    expect(_dialogueText(dialogues[1]), 'one, two, three');
    // Nine commas delimit the fixed fields; the rest belongs to the text.
    expect(dialogues[1].split(',').length, greaterThan(10));
  });

  test('writes the header, two styles and Chinese-first dialogue lines', () {
    final ass = buildBilingualAss(
      segments: _segments,
      translations: const {1: '你好，世界', 2: '第二行'},
    );

    expect(ass, contains('[Script Info]'));
    expect(ass, contains('PlayResX: $kAssPlayResX'));
    expect(ass, contains('PlayResY: $kAssPlayResY'));
    expect(ass, contains('[V4+ Styles]'));
    expect(ass, contains('[Events]'));
    expect(ass, contains('Format: Layer, Start, End, Style, Name, MarginL, '
        'MarginR, MarginV, Effect, Text'));

    final chinese = _style(ass, kChineseStyle);
    final original = _style(ass, kOriginalStyle);
    expect(_fontSize(chinese), greaterThan(_fontSize(original)));
    // Alignment 2 = bottom center; the Chinese line sits higher because it is
    // placed above the original line.
    expect(_alignment(chinese), 2);
    expect(_alignment(original), 2);
    expect(_marginV(chinese), greaterThan(_marginV(original)));

    final dialogues = _dialogues(ass);
    expect(dialogues, hasLength(4));
    // Chinese line first, original second, for each segment.
    expect(dialogues[0], contains(',$kChineseStyle,'));
    expect(dialogues[0], startsWith('Dialogue: 0,0:00:01.00,0:00:02.50,'));
    expect(_dialogueText(dialogues[0]), '你好，世界');
    expect(dialogues[1], contains(',$kOriginalStyle,'));
    expect(dialogues[1], startsWith('Dialogue: 0,0:00:01.00,0:00:02.50,'));
    expect(_dialogueText(dialogues[1]), 'Hello, world');
    expect(dialogues[2], contains(',$kChineseStyle,'));
    expect(_dialogueText(dialogues[2]), '第二行');
    expect(dialogues[3], contains(',$kOriginalStyle,'));
    expect(_dialogueText(dialogues[3]), 'Second line');
    expect(dialogues[2], startsWith('Dialogue: 0,0:01:02.00,0:01:04.00,'));
  });

  test('escapes dialogue text and falls back to the original line', () {
    final ass = buildBilingualAss(
      segments: const [
        TranscriptSegment(
          id: 3,
          start: Duration.zero,
          end: Duration(seconds: 1),
          text: r'{override}\N raw',
        ),
        TranscriptSegment(
          id: 4,
          start: Duration(seconds: 1),
          end: Duration(seconds: 2),
          text: 'no translation',
        ),
      ],
      translations: const {3: r'{译文}'},
    );
    final dialogues = _dialogues(ass);
    expect(_dialogueText(dialogues[0]), r'\{译文\}');
    expect(_dialogueText(dialogues[1]), r'\{override\}\\N raw');
    expect(_dialogueText(dialogues[2]), 'no translation');
    expect(_dialogueText(dialogues[3]), 'no translation');
  });

  test('gives a zero-length segment a usable duration', () {
    final ass = buildBilingualAss(
      segments: const [
        TranscriptSegment(
          id: 1,
          start: Duration(seconds: 5),
          end: Duration(seconds: 5),
          text: 'hi',
        ),
      ],
      translations: const {},
    );
    expect(_dialogues(ass).first, startsWith('Dialogue: 0,0:00:05.00,'
        '0:00:05.50,'));
  });

  test('builds a Chinese-only SRT', () {
    final srt = buildChineseSrt(
      segments: _segments,
      translations: const {1: '你好，世界', 2: '第二行'},
    );
    expect(
      srt,
      '1\n'
      '00:00:01,000 --> 00:00:02,500\n'
      '你好，世界\n'
      '\n'
      '2\n'
      '00:01:02,005 --> 00:01:04,000\n'
      '第二行\n'
      '\n',
    );
  });

  test('SRT keeps the original text when a translation is missing', () {
    final srt = buildChineseSrt(
      segments: _segments,
      translations: const {},
    );
    expect(srt, contains('Hello, world'));
    expect(srt, contains('Second line'));
  });

  test('empty input still produces valid documents', () {
    final ass = buildBilingualAss(segments: const [], translations: const {});
    expect(ass, contains('[Events]'));
    expect(_dialogues(ass), isEmpty);
    expect(buildChineseSrt(segments: const [], translations: const {}), '');
  });
}
