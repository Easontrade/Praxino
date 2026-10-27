import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class WebDavEntry {
  const WebDavEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.length,
    this.contentType,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final int? length;
  final String? contentType;
}

class WebDavException implements Exception {
  const WebDavException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WebDavAuthException extends WebDavException {
  const WebDavAuthException(super.message);
}

/// Minimal WebDAV client: PROPFIND Depth: 1 + Basic auth.
class WebDavClient {
  WebDavClient({
    required this.baseUrl,
    required this.username,
    required this.password,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String username;
  final String password;
  final http.Client _client;

  Map<String, String> get headers => {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$username:$password'))}',
        'Depth': '1',
        'Content-Type': 'application/xml; charset=utf-8',
      };

  Uri uriFor(String path) {
    final base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
    final normalizedBase = base.toString().replaceAll(RegExp(r'/+$'), '');
    final segments = path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    return Uri.parse(segments.isEmpty ? normalizedBase : '$normalizedBase/$segments');
  }

  Future<List<WebDavEntry>> list(String path) async {
    final uri = uriFor(path);
    final response = await _client.send(http.Request('PROPFIND', uri)
      ..headers.addAll(headers)
      ..body = _body);
    final bytes = await response.stream.toBytes();
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const WebDavAuthException('WebDAV 认证失败');
    }
    if (response.statusCode >= 400) {
      throw WebDavException('WebDAV HTTP ${response.statusCode}');
    }
    return _parse(bytes, uri);
  }

  List<WebDavEntry> _parse(List<int> bytes, Uri requestUri) {
    final basePath = Uri.parse(baseUrl).path.replaceAll(RegExp(r'/$'), '');
    final requestPath = requestUri.path.startsWith(basePath)
        ? requestUri.path.substring(basePath.length)
        : requestUri.path;
    final document = XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
    final entries = <WebDavEntry>[];
    for (final response in document.descendants.whereType<XmlElement>()) {
      if (response.name.local != 'response') continue;
      final hrefElement = response.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'href')
          .firstOrNull;
      if (hrefElement == null) continue;
      final href = Uri.tryParse(hrefElement.innerText.trim());
      if (href == null) continue;
      final resolved = requestUri.resolveUri(href);
      var rawPath = Uri.decodeComponent(resolved.path);
      if (basePath.isNotEmpty && rawPath.startsWith(basePath)) {
        rawPath = rawPath.substring(basePath.length);
      }
      if (!rawPath.startsWith('/')) rawPath = '/$rawPath';
      if (rawPath == '/' && requestPath != '/') continue;
      final isDirectory = response.descendants
          .whereType<XmlElement>()
          .any((element) => element.name.local == 'collection');
      final name = response.descendants
              .whereType<XmlElement>()
              .where((element) => element.name.local == 'displayname')
              .map((element) => element.innerText.trim())
              .firstOrNull ??
          _basename(rawPath);
      final length = int.tryParse(response.descendants
              .whereType<XmlElement>()
              .where((element) => element.name.local == 'getcontentlength')
              .map((element) => element.innerText.trim())
              .firstOrNull ??
          '');
      final contentType = response.descendants
          .whereType<XmlElement>()
          .where((element) => element.name.local == 'getcontenttype')
          .map((element) => element.innerText.trim())
          .firstOrNull;
      final path = rawPath.endsWith('/') && rawPath.length > 1
          ? rawPath.substring(0, rawPath.length - 1)
          : rawPath;
      if (path == requestPath && !isDirectory) continue;
      entries.add(WebDavEntry(
        path: path,
        name: name.isEmpty ? _basename(path) : name,
        isDirectory: isDirectory,
        length: length,
        contentType: contentType,
      ));
    }
    return entries;
  }

  static String _basename(String path) {
    final segments = path.split('/').where((segment) => segment.isNotEmpty).toList();
    return segments.isEmpty ? path : segments.last;
  }

  void close() => _client.close();
}

const String _body = '''<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname/>
    <d:resourcetype/>
    <d:getcontentlength/>
    <d:getcontenttype/>
  </d:prop>
</d:propfind>''';
