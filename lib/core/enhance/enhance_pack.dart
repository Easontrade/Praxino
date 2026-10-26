import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Describes one downloadable libmpv build with VapourSynth support.
class EnhancePackManifest {
  const EnhancePackManifest({
    required this.version,
    required this.url,
    required this.sha256,
    this.fileName = 'libmpv-2.dll',
  });

  final String version;
  final String url;
  final String sha256;
  final String fileName;

  Map<String, Object?> toJson() => {
        'version': version,
        'url': url,
        'sha256': sha256,
        'fileName': fileName,
      };

  static EnhancePackManifest? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final version = json['version'];
    final url = json['url'];
    final sha256 = json['sha256'];
    if (version is! String || url is! String || sha256 is! String) {
      return null;
    }
    if (version.isEmpty || url.isEmpty || sha256.length != 64) return null;
    return EnhancePackManifest(
      version: version,
      url: url,
      sha256: sha256.toLowerCase(),
      fileName:
          json['fileName'] is String ? json['fileName'] as String : 'libmpv-2.dll',
    );
  }
}

class EnhancePackException implements Exception {
  const EnhancePackException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Downloads a single file into the enhance-pack directory and verifies it.
///
/// The manifest points at the libmpv DLL directly; archive extraction can be
/// added later without changing the verification step.
class EnhancePackDownloader {
  EnhancePackDownloader({
    required String root,
    http.Client? client,
  })  : _root = Directory(root),
        _client = client ?? http.Client();

  final Directory _root;
  final http.Client _client;

  File fileFor(EnhancePackManifest manifest) =>
      File(p.join(_root.path, manifest.fileName));

  Future<bool> isInstalled(EnhancePackManifest manifest) async {
    final file = fileFor(manifest);
    if (!await file.exists()) return false;
    final digest = sha256.convert(await file.readAsBytes()).toString();
    return digest == manifest.sha256;
  }

  Future<File> download(EnhancePackManifest manifest) async {
    await _root.create(recursive: true);
    final response = await _client.get(Uri.parse(manifest.url));
    if (response.statusCode >= 400) {
      throw EnhancePackException('增强包下载失败：HTTP ${response.statusCode}');
    }
    final digest = sha256.convert(response.bodyBytes).toString();
    if (digest != manifest.sha256) {
      throw const EnhancePackException('增强包校验失败（SHA256 不匹配）');
    }
    final target = fileFor(manifest);
    final temp = File('${target.path}.part');
    await temp.writeAsBytes(response.bodyBytes, flush: true);
    await temp.rename(target.path);
    return target;
  }

  void close() => _client.close();
}

/// Small helper for tooling/tests: the SHA256 of a byte list.
String sha256Hex(List<int> bytes) =>
    sha256.convert(bytes).toString();

/// Convenience for JSON manifests embedded in tests/tools.
String encodeManifest(EnhancePackManifest manifest) =>
    jsonEncode(manifest.toJson());
