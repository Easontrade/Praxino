import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// One downloadable component of an enhancement pack.
///
/// [license] is required: the installer shows it before downloading, so a
/// manifest that forgets to document a license is rejected instead of quietly
/// redistributing something we cannot ship.
class EnhancePackFile {
  const EnhancePackFile({
    required this.name,
    required this.url,
    required this.sha256,
    required this.fileName,
    required this.license,
    this.licenseUrl,
    this.archive = false,
    this.extractTo,
    this.stripComponents = 0,
    this.target,
  });

  final String name;
  final String url;
  final String sha256;
  final String fileName;
  final String license;
  final String? licenseUrl;

  /// When true [url] points at a zip that is extracted into [extractTo].
  final bool archive;

  /// Directory (relative to the pack root) that receives the archive.
  final String? extractTo;

  /// How many leading path segments to drop while extracting (release zips
  /// usually wrap everything in a versioned folder).
  final int stripComponents;

  /// For a plain file, where it goes relative to the pack root. Defaults to
  /// [fileName].
  final String? target;

  Map<String, Object?> toJson() => {
        'name': name,
        'url': url,
        'sha256': sha256,
        'fileName': fileName,
        'license': license,
        if (licenseUrl != null) 'licenseUrl': licenseUrl,
        if (archive) 'archive': true,
        if (extractTo != null) 'extractTo': extractTo,
        if (stripComponents != 0) 'stripComponents': stripComponents,
        if (target != null) 'target': target,
      };

  static EnhancePackFile? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final url = json['url'];
    final sha256 = json['sha256'];
    final fileName = json['fileName'];
    final license = json['license'];
    if (name is! String ||
        url is! String ||
        sha256 is! String ||
        fileName is! String ||
        license is! String) {
      return null;
    }
    if (name.isEmpty ||
        !_sha256Pattern.hasMatch(sha256) ||
        !_httpUrl.hasMatch(url) ||
        fileName.isEmpty ||
        license.trim().isEmpty) {
      return null;
    }
    final extractTo = json['extractTo'];
    final target = json['target'];
    final strip = json['stripComponents'];
    if (extractTo != null && extractTo is! String) return null;
    if (target != null && target is! String) return null;
    if (strip != null && (strip is! int || strip < 0)) return null;
    final archive = json['archive'] == true;
    if (archive && (extractTo is! String || extractTo.isEmpty)) return null;
    return EnhancePackFile(
      name: name,
      url: url,
      sha256: sha256.toLowerCase(),
      fileName: fileName,
      license: license.trim(),
      licenseUrl: json['licenseUrl'] is String
          ? json['licenseUrl'] as String
          : null,
      archive: archive,
      extractTo: extractTo as String?,
      stripComponents: strip is int ? strip : 0,
      target: target as String?,
    );
  }
}

/// A manifest with everything needed for one-click installation.
class EnhancePackBundle {
  const EnhancePackBundle({
    required this.version,
    required this.files,
    this.name = '增强包',
  });

  final String version;
  final String name;
  final List<EnhancePackFile> files;

  Map<String, Object?> toJson() => {
        'version': version,
        'name': name,
        'files': files.map((file) => file.toJson()).toList(),
      };

  static EnhancePackBundle? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final version = json['version'];
    final rawFiles = json['files'];
    if (version is! String || version.isEmpty || rawFiles is! List) {
      return null;
    }
    final files = rawFiles.map(EnhancePackFile.tryFromJson).toList();
    if (files.isEmpty || files.any((file) => file == null)) return null;
    return EnhancePackBundle(
      version: version,
      name: json['name'] is String ? json['name'] as String : '增强包',
      files: files.cast<EnhancePackFile>(),
    );
  }
}

class EnhancePackBundleException implements Exception {
  const EnhancePackBundleException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Where the installer found the two directories the player needs.
class EnhancePackInstallResult {
  const EnhancePackInstallResult({
    required this.installedFiles,
    this.pythonDir,
    this.siteDir,
    this.libmpvPath,
  });

  final List<String> installedFiles;
  final String? pythonDir;
  final String? siteDir;
  final String? libmpvPath;

  bool get hasVapourSynth => pythonDir != null && siteDir != null;
}

/// Downloads, verifies and extracts every file in a [EnhancePackBundle].
class EnhancePackInstaller {
  EnhancePackInstaller({
    required String root,
    http.Client? client,
    this.onProgress,
    this.timeout = const Duration(minutes: 10),
  })  : _root = Directory(root),
        _client = client ?? http.Client();

  final Directory _root;
  final http.Client _client;
  final Duration timeout;

  /// Receives a short human-readable status before each download.
  final void Function(String message)? onProgress;

  /// Downloads a manifest URL and parses it; accepts both a bundle and the
  /// older single-libmpv manifest.
  Future<Object> fetchManifest(String url) async {
    if (!_httpUrl.hasMatch(url)) {
      throw const EnhancePackBundleException('manifest 地址必须是 http(s)');
    }
    final response = await _client.get(Uri.parse(url)).timeout(timeout);
    if (response.statusCode >= 400) {
      throw EnhancePackBundleException(
        'manifest 下载失败：HTTP ${response.statusCode}',
      );
    }
    if (response.bodyBytes.length > 1024 * 1024) {
      throw const EnhancePackBundleException('manifest 太大（超过 1 MiB）');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (error) {
      throw EnhancePackBundleException('manifest 不是合法 JSON：${error.message}');
    }
  }

  Future<EnhancePackInstallResult> install(EnhancePackBundle bundle) async {
    await _root.create(recursive: true);
    final downloads = Directory(p.join(_root.path, '.downloads'));
    await downloads.create(recursive: true);
    final installed = <String>[];
    String? libmpvPath;
    try {
      for (var index = 0; index < bundle.files.length; index++) {
        final file = bundle.files[index];
        onProgress?.call(
          '正在下载 ${file.name}（${index + 1}/${bundle.files.length}）…',
        );
        final bytes = await _download(file, downloads, index + 1, bundle.files.length);
        if (file.archive) {
          final destination = _safeJoin(
            _root.path,
            file.extractTo ?? p.basenameWithoutExtension(file.fileName),
          );
          _extractZip(bytes, destination, file.stripComponents);
          installed.add(destination);
        } else {
          final target = File(_safeJoin(
            _root.path,
            file.target ?? file.fileName,
          ));
          target.parent.createSync(recursive: true);
          await target.writeAsBytes(bytes, flush: true);
          installed.add(target.path);
          if (p.basename(target.path).toLowerCase() == 'libmpv-2.dll') {
            libmpvPath = target.path;
          }
        }
      }
    } finally {
      try {
        if (await downloads.exists()) await downloads.delete(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup; a failed delete must not hide the install error.
      }
    }
    return EnhancePackInstallResult(
      installedFiles: installed,
      pythonDir: EnhancePackLayout.findPythonDir(_root.path),
      siteDir: EnhancePackLayout.findSiteDir(_root.path),
      libmpvPath: libmpvPath,
    );
  }

  Future<List<int>> _download(
    EnhancePackFile file,
    Directory downloads,
    int index,
    int total,
  ) async {
    final request = http.Request('GET', Uri.parse(file.url));
    final response = await _client.send(request).timeout(timeout);
    if (response.statusCode >= 400) {
      throw EnhancePackBundleException(
        '${file.name} 下载失败：HTTP ${response.statusCode}',
      );
    }
    final temp = File(
      p.join(downloads.path, '${index}_${p.basename(file.fileName)}.part'),
    );
    final sink = temp.openWrite();
    try {
      await response.stream.timeout(timeout).pipe(sink);
    } finally {
      await sink.close();
    }
    try {
      final bytes = await temp.readAsBytes();
      final digest = sha256.convert(bytes).toString();
      if (digest != file.sha256) {
        throw EnhancePackBundleException('${file.name} 校验失败（SHA256 不匹配）');
      }
      return bytes;
    } finally {
      try {
        if (await temp.exists()) await temp.delete();
      } on FileSystemException {
        // Best-effort cleanup.
      }
    }
  }

  void _extractZip(List<int> bytes, String destination, int stripComponents) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final root = p.normalize(p.absolute(destination));
    for (final entry in archive) {
      if (!entry.isFile) continue;
      var parts = entry.name
          .replaceAll('\\', '/')
          .split('/')
          .where((part) => part.isNotEmpty && part != '.')
          .toList();
      if (parts.any((part) => part == '..')) {
        throw const EnhancePackBundleException('增强包内有非法路径');
      }
      if (stripComponents > 0) {
        if (parts.length <= stripComponents) continue;
        parts = parts.sublist(stripComponents);
      }
      if (parts.isEmpty) continue;
      final target = p.normalize(p.join(root, p.joinAll(parts)));
      if (!p.isWithin(root, target)) {
        throw const EnhancePackBundleException('增强包内有非法路径');
      }
      final file = File(target);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(entry.content as List<int>, flush: true);
    }
  }

  void close() => _client.close();
}

/// Finds the extracted Python and VapourSynth directories without asking the
/// user to type paths.
class EnhancePackLayout {
  EnhancePackLayout._();

  static String? findPythonDir(String root) {
    for (final file in _walk(root, maxDepth: 4)) {
      if (file is! File) continue;
      if (_pythonDll.hasMatch(p.basename(file.path).toLowerCase())) {
        return p.dirname(file.path);
      }
    }
    return null;
  }

  static String? findSiteDir(String root) {
    for (final entity in _walk(root, maxDepth: 6)) {
      if (entity is! Directory) continue;
      if (File(p.join(entity.path, 'vsscript.dll')).existsSync() &&
          File(p.join(entity.path, 'vapoursynth.pyd')).existsSync()) {
        return entity.path;
      }
    }
    return null;
  }

  static List<FileSystemEntity> _walk(String root, {required int maxDepth}) {
    final directory = Directory(root);
    if (!directory.existsSync()) return const [];
    final rootDepth = p.split(p.normalize(root)).length;
    try {
      return directory
          .listSync(recursive: true, followLinks: false)
          .where((entity) {
        final depth = p.split(p.normalize(entity.path)).length - rootDepth;
        return depth <= maxDepth;
      }).toList();
    } on FileSystemException {
      return const [];
    }
  }

  static final _pythonDll = RegExp(r'^python3\d+\.dll$');
}

String _safeJoin(String root, String relative) {
  if (p.isAbsolute(relative)) {
    throw const EnhancePackBundleException('增强包路径不能是绝对路径');
  }
  final rootPath = p.normalize(p.absolute(root));
  final target = p.normalize(p.join(rootPath, relative));
  if (!p.isWithin(rootPath, target) && target != rootPath) {
    throw const EnhancePackBundleException('增强包路径越出了安装目录');
  }
  return target;
}

final _sha256Pattern = RegExp(r'^[0-9a-fA-F]{64}$');
final _httpUrl = RegExp(r'^https?://');
