import 'dart:convert';

import 'package:http/http.dart' as http;

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.url,
    this.notes = '',
  });

  final String version;
  final String url;
  final String notes;
}

/// Checks the latest GitHub release. Failures are silent by design.
class UpdateChecker {
  UpdateChecker({
    this.repository = 'Easontrade/Praxino',
    required this.currentVersion,
    this.skippedVersion,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String repository;
  final String currentVersion;
  final String? skippedVersion;
  final http.Client _client;

  Future<UpdateInfo?> check() async {
    try {
      final response = await _client.get(
        Uri.parse('https://api.github.com/repos/$repository/releases/latest'),
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'Praxino',
        },
      );
      if (response.statusCode >= 400) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) return null;
      final tag = decoded['tag_name'];
      if (tag is! String) return null;
      final version = tag.replaceFirst(RegExp(r'^v'), '');
      if (compareVersions(version, currentVersion) <= 0) return null;
      if (skippedVersion != null && compareVersions(version, skippedVersion!) == 0) {
        return null;
      }
      return UpdateInfo(
        version: version,
        url: '${decoded['html_url'] ?? 'https://github.com/$repository/releases'}',
        notes: '${decoded['body'] ?? ''}',
      );
    } on Exception {
      return null;
    }
  }

  /// Numeric semver comparison; build metadata is ignored.
  static int compareVersions(String a, String b) {
    List<int> parse(String value) {
      final core = value.split('+').first.split('-').first;
      return [
        for (final part in core.split('.'))
          int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
      ];
    }

    final left = parse(a);
    final right = parse(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }

  void close() => _client.close();
}
