import 'dart:convert';

import 'package:http/http.dart' as http;

import 'transcript.dart';
import 'translator.dart';

/// DeepSeek models offered by the settings page. The id stays a free-form
/// setting, so a newer model can be typed in without touching code.
class DeepSeekModels {
  DeepSeekModels._();

  static const chat = 'deepseek-chat';
  static const reasoner = 'deepseek-reasoner';

  static const known = [chat, reasoner];
}

/// OpenAI-compatible endpoint; the settings page exposes it so users can point
/// at a proxy or another compatible service.
const String kDeepSeekEndpoint = 'https://api.deepseek.com/v1/chat/completions';

/// DeepSeek (OpenAI-compatible chat completions) translator.
///
/// The client is injectable so tests can use `package:http/testing.dart` and
/// never touch the network. Every failure is reported as a Chinese
/// [TranslationException]; the API key is never echoed back.
class DeepSeekTranslator implements Translator {
  DeepSeekTranslator({
    required this.apiKey,
    this.model = DeepSeekModels.chat,
    http.Client? client,
    Uri? endpoint,
    this.maxTokens = 8192,
    this.maxRetries = 1,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _endpoint = endpoint ?? Uri.parse(kDeepSeekEndpoint);

  final String apiKey;
  @override
  final String model;
  final int maxTokens;

  /// How many extra attempts a batch gets when the model skipped ids.
  final int maxRetries;

  final http.Client _client;
  final bool _ownsClient;
  final Uri _endpoint;

  void close() {
    if (_ownsClient) _client.close();
  }

  @override
  Future<Map<String, String>> extractGlossary(
    List<TranscriptSegment> segments,
  ) async {
    if (segments.isEmpty) return const {};
    final text = await _complete(
      system: _glossarySystem,
      user: _glossaryUser(segments),
      maxTokens: 2048,
    );
    return _parseGlossary(text);
  }

  @override
  Future<TranslationResult> translate(TranslationRequest request) async {
    final segments = request.batch.segments;
    if (segments.isEmpty) return const TranslationResult(translations: {});
    final expected = [for (final segment in segments) segment.id];
    final originals = {
      for (final segment in segments) segment.id: segment.text,
    };
    final collected = <int, String>{};

    await _translateOnce(request, expected, collected);
    var missing = expected.where((id) => !collected.containsKey(id)).toList();
    if (missing.isNotEmpty && maxRetries > 0) {
      final retrySegments =
          segments.where((segment) => missing.contains(segment.id)).toList();
      final retry = TranslationRequest(
        batch: TranslationBatch(
          segments: retrySegments,
          contextBefore: request.batch.contextBefore,
          contextAfter: request.batch.contextAfter,
        ),
        glossary: request.glossary,
        sourceLanguage: request.sourceLanguage,
      );
      try {
        await _translateOnce(retry, missing, collected);
      } on TranslationException {
        // The retry is best effort; the remaining ids fall back to the
        // original text below.
      }
      missing = expected.where((id) => !collected.containsKey(id)).toList();
    }

    final translations = <int, String>{};
    final fallbackIds = <int>{};
    for (final id in expected) {
      final chinese = collected[id];
      if (chinese == null) {
        translations[id] = originals[id] ?? '';
        fallbackIds.add(id);
      } else {
        translations[id] = chinese;
      }
    }
    return TranslationResult(
      translations: translations,
      fallbackIds: fallbackIds,
    );
  }

  Future<void> _translateOnce(
    TranslationRequest request,
    List<int> ids,
    Map<int, String> into,
  ) async {
    final text = await _complete(
      system: _translationSystem,
      user: _translationUser(request),
    );
    final allowed = ids.toSet();
    into.addAll(_parseTranslations(text, allowed));
  }

  Future<String> _complete({
    required String system,
    required String user,
    int? maxTokens,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw const TranslationException(
          '未配置 DeepSeek API Key，请在“设置 → AI 双语字幕”里填写');
    }
    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'max_tokens': maxTokens ?? this.maxTokens,
      'temperature': 0.3,
      'stream': false,
    });
    final http.Response response;
    try {
      response = await _client.post(
        _endpoint,
        headers: {
          'Authorization': 'Bearer $key',
          'content-type': 'application/json',
        },
        body: body,
      );
    } on http.ClientException catch (error) {
      throw TranslationException('调用 DeepSeek 失败：${error.message}');
    } on Exception catch (error) {
      throw TranslationException('调用 DeepSeek 失败：$error');
    }
    if (response.statusCode != 200) throw _error(response);
    return _textOf(response.body);
  }

  TranslationException _error(http.Response response) {
    final code = response.statusCode;
    if (code == 401 || code == 403) {
      return const TranslationException('DeepSeek API Key 无效或没有权限（HTTP 401/403）');
    }
    if (code == 402) {
      return const TranslationException('DeepSeek 账户余额不足（HTTP 402）');
    }
    if (code == 429) {
      return const TranslationException('DeepSeek 请求太频繁或额度不足（HTTP 429），请稍后重试');
    }
    if (code >= 500) {
      return TranslationException('DeepSeek 服务暂时不可用（HTTP $code）');
    }
    final detail = _oneLine(response.body, 200);
    return TranslationException(
      detail.isEmpty ? 'DeepSeek 返回 HTTP $code' : 'DeepSeek 返回 HTTP $code：$detail',
    );
  }

  String _textOf(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const TranslationException('DeepSeek 返回的内容不是 JSON');
    }
    if (decoded is! Map) {
      throw const TranslationException('DeepSeek 返回的内容格式不对');
    }
    final choices = decoded['choices'];
    if (choices is List) {
      for (final choice in choices) {
        if (choice is! Map) continue;
        final message = choice['message'];
        if (message is! Map) continue;
        final content = message['content'];
        if (content is String && content.trim().isNotEmpty) {
          return content;
        }
        if (content is List) {
          final buffer = StringBuffer();
          for (final part in content) {
            if (part is Map && part['text'] is String) {
              buffer.write(part['text']);
            }
          }
          if (buffer.toString().trim().isNotEmpty) return buffer.toString();
        }
      }
    }
    throw const TranslationException('DeepSeek 返回的内容里没有可用的文本');
  }
}

const String _glossarySystem = '你是影视字幕翻译助手。只输出 JSON，不要输出解释或 Markdown 代码块。';

const String _translationSystem = '你是专业的影视字幕翻译，把外语字幕翻译成自然、口语化的简体中文。'
    '人名和术语使用给定的固定译法。严格按输入的 id 逐条翻译，不要合并、拆分或增删句子。'
    '只输出 JSON 数组，不要输出解释或 Markdown 代码块。';

String _glossaryUser(List<TranscriptSegment> segments) {
  final joined = segments.map((segment) => segment.text).join('\n');
  final clipped =
      joined.length > 20000 ? joined.substring(0, 20000) : joined;
  return '下面是一集视频的字幕原文。找出人名、地名、组织名、专有名词和需要固定译法的术语，'
      '给出简体中文译名。\n'
      '只输出 JSON 数组，每项形如 {"source":"原文","target":"中文"}；没有这类词就输出 []。\n\n'
      '字幕原文：\n$clipped';
}

String _translationUser(TranslationRequest request) {
  final batch = request.batch;
  final buffer = StringBuffer();
  final language = (request.sourceLanguage ?? '').trim();
  if (language.isNotEmpty) {
    buffer.writeln('源语言：$language');
    buffer.writeln();
  }
  if (request.glossary.isNotEmpty) {
    buffer.writeln('术语表（必须一致使用）：');
    request.glossary.forEach((source, target) {
      buffer.writeln('$source → $target');
    });
    buffer.writeln();
  }
  if (batch.contextBefore.isNotEmpty) {
    buffer.writeln('前文（仅供理解上下文，不要翻译）：');
    for (final segment in batch.contextBefore) {
      buffer.writeln(segment.text);
    }
    buffer.writeln();
  }
  if (batch.contextAfter.isNotEmpty) {
    buffer.writeln('后文（仅供理解上下文，不要翻译）：');
    for (final segment in batch.contextAfter) {
      buffer.writeln(segment.text);
    }
    buffer.writeln();
  }
  buffer.writeln('待翻译字幕（逐条翻译，按 id 对齐）：');
  for (final segment in batch.segments) {
    buffer.writeln('${segment.id}\t${segment.text}');
  }
  buffer.writeln();
  buffer.writeln('输出 JSON 数组，每项形如 {"id":1,"zh":"简体中文翻译"}，'
      'id 必须与输入一致，不要输出其它内容。');
  return buffer.toString();
}

/// Parses the translation array; tolerates fenced JSON and a wrapper object.
Map<int, String> _parseTranslations(String text, Set<int> allowed) {
  final result = <int, String>{};
  final items = _extractArray(text);
  if (items == null) return result;
  for (final item in items) {
    if (item is! Map) continue;
    final id = item['id'];
    final chinese = item['zh'] ?? item['translation'] ?? item['text'];
    if (id is! num || chinese is! String) continue;
    final trimmed = chinese.trim();
    final key = id.toInt();
    if (trimmed.isEmpty || !allowed.contains(key)) continue;
    result[key] = trimmed;
  }
  return result;
}

Map<String, String> _parseGlossary(String text) {
  final result = <String, String>{};
  final items = _extractArray(text);
  if (items == null) return result;
  for (final item in items) {
    if (item is! Map) continue;
    final source = item['source'] ?? item['term'] ?? item['original'];
    final target = item['target'] ?? item['translation'] ?? item['zh'];
    if (source is! String || target is! String) continue;
    final key = source.trim();
    final value = target.trim();
    if (key.isEmpty || value.isEmpty) continue;
    result[key] = value;
    if (result.length >= 100) break;
  }
  return result;
}

/// Accepts `[...]`, `{"translations":[...]}`, fenced JSON and JSON embedded in
/// prose (the model occasionally adds a sentence before the array).
List<Object?>? _extractArray(String raw) {
  final cleaned = _stripFence(raw).trim();
  final list = _asList(_decode(cleaned));
  if (list != null) return list;
  final start = cleaned.indexOf('[');
  final end = cleaned.lastIndexOf(']');
  if (start >= 0 && end > start) {
    return _asList(_decode(cleaned.substring(start, end + 1)));
  }
  return null;
}

Object? _decode(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

List<Object?>? _asList(Object? decoded) {
  if (decoded is List) return decoded;
  if (decoded is Map) {
    for (final key in const ['translations', 'segments', 'items', 'results']) {
      final value = decoded[key];
      if (value is List) return value;
    }
  }
  return null;
}

String _stripFence(String raw) {
  final trimmed = raw.trim();
  if (!trimmed.contains('```')) return trimmed;
  final start = trimmed.indexOf('```');
  var body = trimmed.substring(start + 3);
  if (body.toLowerCase().startsWith('json')) body = body.substring(4);
  final end = body.indexOf('```');
  if (end >= 0) body = body.substring(0, end);
  return body.trim();
}

String _oneLine(String value, int maxLength) {
  final line = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (line.length <= maxLength) return line;
  return '${line.substring(0, maxLength)}…';
}
