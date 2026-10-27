import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:praxino/core/subtitles/ai/claude_translator.dart';
import 'package:praxino/core/subtitles/ai/transcript.dart';
import 'package:praxino/core/subtitles/ai/translator.dart';

http.Response _claudeResponse(String text) => http.Response.bytes(
      utf8.encode(jsonEncode({
        'content': [
          {'type': 'text', 'text': text},
        ],
      })),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

TranscriptSegment _segment(int id, String text) => TranscriptSegment(
      id: id,
      start: Duration(seconds: id),
      end: Duration(seconds: id + 1),
      text: text,
    );

TranslationBatch _batch(List<TranscriptSegment> segments) =>
    TranslationBatch(segments: segments);

void main() {
  test('posts a Messages request and aligns the JSON result by id', () async {
    final requests = <http.Request>[];
    final translator = ClaudeTranslator(
      apiKey: 'test-key',
      client: MockClient((request) async {
        requests.add(request);
        return _claudeResponse('[{"id":1,"zh":"你好"},{"id":2,"zh":"再见"}]');
      }),
    );

    final result = await translator.translate(TranslationRequest(
      batch: _batch([_segment(1, 'Hello'), _segment(2, 'Bye')]),
    ));

    expect(result.translations, {1: '你好', 2: '再见'});
    expect(result.fallbackIds, isEmpty);

    final request = requests.single;
    expect(request.url.toString(), 'https://api.anthropic.com/v1/messages');
    expect(request.method, 'POST');
    expect(request.headers['x-api-key'], 'test-key');
    expect(request.headers['anthropic-version'], '2023-06-01');
    expect(request.headers['content-type'], startsWith('application/json'));

    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['model'], ClaudeModels.haiku);
    expect(body['max_tokens'], isA<int>());
    expect(body['messages'], hasLength(1));
    expect(request.body, contains('Hello'));
  });

  test('sends context lines and the glossary with the batch', () async {
    final requests = <http.Request>[];
    final translator = ClaudeTranslator(
      apiKey: 'test-key',
      client: MockClient((request) async {
        requests.add(request);
        return _claudeResponse('[{"id":2,"zh":"普拉克西诺启动"}]');
      }),
    );

    await translator.translate(TranslationRequest(
      batch: TranslationBatch(
        segments: [_segment(2, 'Praxino starts')],
        contextBefore: [_segment(1, 'Previously on')],
        contextAfter: [_segment(3, 'Next time')],
      ),
      glossary: const {'Praxino': '普拉克西诺'},
      sourceLanguage: 'en',
    ));

    final body = requests.single.body;
    expect(body, contains('普拉克西诺'));
    expect(body, contains('术语表'));
    expect(body, contains('Previously on'));
    expect(body, contains('Next time'));
    expect(body, contains('源语言：en'));
    expect(body, contains('Praxino starts'));
  });

  test('parses a fenced JSON answer', () async {
    final translator = ClaudeTranslator(
      apiKey: 'test-key',
      client: MockClient((request) async => _claudeResponse(
            '```json\n[{"id":1,"zh":"你好"}]\n```',
          )),
    );

    final result = await translator.translate(TranslationRequest(
      batch: _batch([_segment(1, 'Hello')]),
    ));

    expect(result.translations[1], '你好');
  });

  test('parses a JSON array embedded in prose', () async {
    final translator = ClaudeTranslator(
      apiKey: 'test-key',
      client: MockClient((request) async => _claudeResponse(
            'Here is the result:\n[{"id":1,"zh":"你好"}]\nDone.',
          )),
    );

    final result = await translator.translate(TranslationRequest(
      batch: _batch([_segment(1, 'Hello')]),
    ));

    expect(result.translations[1], '你好');
    expect(result.fallbackIds, isEmpty);
  });

  test('retries once for ids the model skipped', () async {
    var calls = 0;
    final translator = ClaudeTranslator(
      apiKey: 'test-key',
      client: MockClient((request) async {
        calls++;
        if (calls == 1) {
          // The model dropped id 2 and hallucinated id 99.
          return _claudeResponse('[{"id":1,"zh":"你好"},{"id":99,"zh":"多出来"}]');
        }
        return _claudeResponse('[{"id":2,"zh":"再见"}]');
      }),
    );

    final result = await translator.translate(TranslationRequest(
      batch: _batch([_segment(1, 'Hello'), _segment(2, 'Bye')]),
    ));

    expect(calls, 2);
    expect(result.translations, {1: '你好', 2: '再见'});
    expect(result.translations.containsKey(99), isFalse);
    expect(result.fallbackIds, isEmpty);
  });

  test('falls back to the original text when the retry also misses it',
      () async {
    var calls = 0;
    final translator = ClaudeTranslator(
      apiKey: 'test-key',
      client: MockClient((request) async {
        calls++;
        return _claudeResponse('[{"id":1,"zh":"你好"}]');
      }),
    );

    final result = await translator.translate(TranslationRequest(
      batch: _batch([_segment(1, 'Hello'), _segment(2, 'Bye')]),
    ));

    expect(calls, 2, reason: 'one attempt plus one retry');
    expect(result.translations, {1: '你好', 2: 'Bye'});
    expect(result.fallbackIds, {2});
  });

  test('keeps the first result when the retry itself fails', () async {
    var calls = 0;
    final translator = ClaudeTranslator(
      apiKey: 'test-key',
      client: MockClient((request) async {
        calls++;
        if (calls == 1) return _claudeResponse('[{"id":1,"zh":"你好"}]');
        return http.Response('gone', 500);
      }),
    );

    final result = await translator.translate(TranslationRequest(
      batch: _batch([_segment(1, 'Hello'), _segment(2, 'Bye')]),
    ));

    expect(calls, 2);
    expect(result.translations[1], '你好');
    expect(result.translations[2], 'Bye');
    expect(result.fallbackIds, {2});
  });

  test('extracts a glossary before translating', () async {
    final bodies = <String>[];
    final translator = ClaudeTranslator(
      apiKey: 'test-key',
      client: MockClient((request) async {
        bodies.add(request.body);
        if (bodies.length == 1) {
          return _claudeResponse(
            '[{"source":"Praxino","target":"普拉克西诺"}]',
          );
        }
        return _claudeResponse('[{"id":1,"zh":"普拉克西诺启动"}]');
      }),
    );

    final segments = [_segment(1, 'Praxino starts')];
    final glossary = await translator.extractGlossary(segments);
    expect(glossary, {'Praxino': '普拉克西诺'});
    expect(bodies.single, contains('人名'));

    final result = await translator.translate(TranslationRequest(
      batch: _batch(segments),
      glossary: glossary,
    ));
    expect(result.translations[1], '普拉克西诺启动');
    expect(bodies.last, contains('普拉克西诺'));
  });

  test('missing API key throws a readable Chinese error without any request',
      () async {
    var called = false;
    final translator = ClaudeTranslator(
      apiKey: '   ',
      client: MockClient((request) async {
        called = true;
        return _claudeResponse('[]');
      }),
    );

    await expectLater(
      translator.translate(
        TranslationRequest(batch: _batch([_segment(1, 'Hello')])),
      ),
      throwsA(isA<TranslationException>().having(
        (error) => error.message,
        'message',
        contains('API Key'),
      )),
    );
    await expectLater(
      translator.extractGlossary([_segment(1, 'Hello')]),
      throwsA(isA<TranslationException>()),
    );
    expect(called, isFalse);
  });

  test('maps HTTP failures to Chinese errors without leaking the key',
      () async {
    final unauthorized = ClaudeTranslator(
      apiKey: 'secret-key-value',
      client: MockClient((request) async => http.Response('nope', 401)),
    );
    await expectLater(
      unauthorized.translate(
        TranslationRequest(batch: _batch([_segment(1, 'Hello')])),
      ),
      throwsA(isA<TranslationException>()
          .having((error) => error.message, 'message', contains('无效'))
          .having((error) => error.message, 'message',
              isNot(contains('secret-key-value')))),
    );

    final unavailable = ClaudeTranslator(
      apiKey: 'secret-key-value',
      client: MockClient((request) async => http.Response('down', 503)),
    );
    await expectLater(
      unavailable.translate(
        TranslationRequest(batch: _batch([_segment(1, 'Hello')])),
      ),
      throwsA(isA<TranslationException>().having(
        (error) => error.message,
        'message',
        contains('暂时不可用'),
      )),
    );
  });

  test('rejects a response that is not JSON', () async {
    final translator = ClaudeTranslator(
      apiKey: 'test-key',
      client: MockClient((request) async => http.Response('not json', 200)),
    );

    await expectLater(
      translator.translate(
        TranslationRequest(batch: _batch([_segment(1, 'Hello')])),
      ),
      throwsA(isA<TranslationException>()),
    );
  });
}
