import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../settings/settings_store.dart';
import 'dandanplay_provider.dart';
import 'danmaku_engine.dart';
import 'danmaku_file_hash.dart';

/// Resolves dandanplay comments for a local file and remembers the match.
class DanmakuService {
  DanmakuService({required this.settings, http.Client? client})
      : _client = client,
        _ownsClient = client == null;

  final SettingsStore settings;
  final http.Client? _client;
  final bool _ownsClient;

  Future<List<DanmakuItem>?> forLocalFile(String path) async {
    final appId = settings.dandanplayAppId;
    final secret = settings.dandanplayAppSecret;
    if (appId.isEmpty || secret.isEmpty) return null;

    final file = File(path);
    if (!await file.exists()) return null;

    final api = DandanplayClient(
      appId: appId,
      appSecret: secret,
      client: _client,
    );
    final store = settings.danmakuMatches;
    final key = p.basenameWithoutExtension(path);
    try {
      final remembered = store.episodeFor(key);
      if (remembered != null) {
        final comments = await api.comments(remembered);
        if (comments.isNotEmpty) return comments;
        await store.forget(key);
      }

      final match = await api.match(
        fileName: p.basename(path),
        fileHash: await DanmakuFileHash.of(file),
        fileSize: await file.length(),
      );
      if (match == null) return null;
      await store.remember(key, match.episodeId);
      return await api.comments(match.episodeId);
    } on Exception {
      return null;
    } finally {
      if (_ownsClient) api.close();
    }
  }

  void close() {
    if (_ownsClient) _client?.close();
  }
}
