import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_qjs_next/flutter_qjs.dart';
import 'package:http/http.dart' as http;

class QuickJsException implements Exception {
  const QuickJsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A fresh QuickJS engine per script run, with no file/process access.
///
/// The only host capability is `fetch`, implemented by an injectable
/// [http.Client] and constrained by [allowUrl]; time and heap are capped.
class QuickJsHost {
  QuickJsHost({
    http.Client? client,
    bool Function(Uri url)? allowUrl,
    this.timeout = const Duration(seconds: 3),
    this.memoryLimit = 64 * 1024 * 1024,
  })  : _client = client ?? http.Client(),
        _allowUrl = allowUrl ?? _defaultAllowUrl;

  final http.Client _client;
  final bool Function(Uri url) _allowUrl;
  final Duration timeout;
  final int memoryLimit;

  static bool _defaultAllowUrl(Uri url) {
    if (url.scheme != 'http' && url.scheme != 'https') return false;
    final host = url.host.toLowerCase();
    if (host == 'localhost' || host == '::1' || host.endsWith('.localhost')) {
      return false;
    }
    if (host.startsWith('127.') ||
        host.startsWith('10.') ||
        host.startsWith('192.168.') ||
        host.startsWith('169.254.')) {
      return false;
    }
    return true;
  }

  Future<Object?> runJson(String code) async {
    final runtime = getJavascriptRuntime(
      stackSize: 8 * 1024 * 1024,
      timeout: timeout.inMilliseconds,
      memoryLimit: memoryLimit,
      webApis: JsWebApis.standard(
        fetch: JsFetchOptions(
          allowUrl: _allowUrl,
          handler: _fetch,
          maxResponseBytes: memoryLimit,
          connectionTimeout: timeout,
        ),
      ),
    );
    try {
      final evaluated = await runtime.evaluateAsync(code);
      final result = await runtime.handlePromise(
        evaluated,
        timeout: timeout + const Duration(seconds: 1),
      );
      if (result.isError) throw QuickJsException(result.stringResult);
      final text = result.stringResult;
      try {
        return jsonDecode(text);
      } on FormatException {
        return text;
      }
    } on QuickJsException {
      rethrow;
    } on Exception catch (error) {
      throw QuickJsException('$error');
    } finally {
      runtime.dispose();
    }
  }

  Future<JsFetchResponse> _fetch(JsFetchRequest request) async {
    final outgoing = http.Request(request.method, request.url)
      ..followRedirects = false;
    for (final header in request.headers) {
      outgoing.headers[header.key] = header.value;
    }
    if (request.body != null) outgoing.bodyBytes = request.body!;
    final response = await _client.send(outgoing);
    return JsFetchResponse(
      status: response.statusCode,
      statusText: response.reasonPhrase ?? '',
      body: response.stream,
      headers: response.headers.entries.toList(),
    );
  }

  void close() => _client.close();
}

/// Small regex helper exposed to scripts; it is not a DOM implementation.
const String quickJsHelpers = r'''
function parseHtml(html, pattern) {
  const match = new RegExp(pattern).exec(String(html));
  return match ? (match[1] ?? match[0]) : null;
}
''';

String scriptHash(String script) =>
    sha256.convert(utf8.encode(script)).toString();
