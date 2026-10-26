import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../danmaku/danmaku_match_store.dart';
import '../enhance/enhance_settings.dart';
import '../enhance/offline/offline_job.dart';
import '../library/watch_history.dart';
import '../sources/extra_source.dart';
import '../sources/subscription.dart';
import '../storage/app_database.dart';
import 'keybindings.dart';

/// User preferences that outlive a single playback.
class SettingsStore {
  SettingsStore._(this._prefs, this._subscriptionRepository);

  static Future<SettingsStore> load({
    SubscriptionRepository? subscriptions,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final store = SettingsStore._(prefs, subscriptions);
    if (subscriptions != null) {
      await subscriptions.migrateFrom(
        _parseSubscriptions(prefs.getString(_subscriptionsKey)),
      );
      store._subscriptions = await subscriptions.load();
    }
    return store;
  }

  final SharedPreferences _prefs;
  final SubscriptionRepository? _subscriptionRepository;
  List<SourceSubscription> _subscriptions = const [];

  static const _enhanceKey = 'enhance.v1';
  static const _recentKey = 'recent.v1';
  static const _watchKey = 'watch_history.v1';
  static const _keysKey = 'keybindings.v1';
  static const _subscriptionsKey = 'subscriptions.v1';
  static const _extraSourcesKey = 'extra_sources.v1';
  static const _dandanAppIdKey = 'danmaku.appId.v1';
  static const _dandanSecretKey = 'danmaku.appSecret.v1';
  static const _openApiKeyKey = 'subtitle.openApiKey.v1';
  static const _openUsernameKey = 'subtitle.openUsername.v1';
  static const _openPasswordKey = 'subtitle.openPassword.v1';
  static const _openTokenKey = 'subtitle.openToken.v1';
  static const _builtDandanAppId =
      String.fromEnvironment('DANDANPLAY_APP_ID');
  static const _builtDandanAppSecret =
      String.fromEnvironment('DANDANPLAY_APP_SECRET');
  static const _builtDandanAppIdB64 =
      String.fromEnvironment('DANDANPLAY_APP_ID_B64');
  static const _builtDandanAppSecretB64 =
      String.fromEnvironment('DANDANPLAY_APP_SECRET_B64');
  static const _offlineJobsKey = 'offline.jobs.v1';
  static const _offlineFfmpegKey = 'offline.ffmpeg.v1';
  static const _offlineEsrganKey = 'offline.esrgan.v1';
  static const _offlineRifeKey = 'offline.rife.v1';
  static const _vpyScriptKey = 'enhance.vpy.v1';
  static const _skippedUpdateKey = 'update.skipped.v1';
  static const _maxRecent = 20;

  /// Enhancement carries over between files and episodes until changed.
  EnhanceSettings get enhance {
    final raw = _prefs.getString(_enhanceKey);
    if (raw == null) return const EnhanceSettings();
    try {
      return EnhanceSettings.fromJson(
          (jsonDecode(raw) as Map).cast<String, Object?>());
    } on FormatException {
      return const EnhanceSettings();
    }
  }

  Future<void> setEnhance(EnhanceSettings value) =>
      _prefs.setString(_enhanceKey, jsonEncode(value.toJson()));

  List<String> get recent => _prefs.getStringList(_recentKey) ?? const [];

  Future<void> addRecent(String path) {
    final list = [path, ...recent.where((e) => e != path)];
    return _prefs.setStringList(_recentKey, list.take(_maxRecent).toList());
  }

  /// Resume points for local files; see [WatchHistory].
  WatchHistory get watchHistory =>
      WatchHistory.fromJson(_prefs.getString(_watchKey));

  Future<void> saveWatchHistory(WatchHistory history) =>
      _prefs.setString(_watchKey, history.toJson());

  /// Player shortcuts, with built-in defaults when nothing was saved.
  Keybindings get keybindings =>
      Keybindings.fromJson(_prefs.getString(_keysKey));

  Future<void> saveKeybindings(Keybindings value) =>
      _prefs.setString(_keysKey, value.toJson());

  /// User-added source subscriptions. Empty until the user adds one.
  List<SourceSubscription> get subscriptions => _subscriptionRepository == null
      ? _parseSubscriptions(_prefs.getString(_subscriptionsKey))
      : List.unmodifiable(_subscriptions);

  Future<void> saveSubscriptions(List<SourceSubscription> value) async {
    _subscriptions = List.of(value);
    final repository = _subscriptionRepository;
    if (repository != null) {
      await repository.save(value);
      return;
    }
    await _prefs.setString(
      _subscriptionsKey,
      jsonEncode(value.map((e) => e.toJson()).toList()),
    );
  }

  static List<SourceSubscription> _parseSubscriptions(String? raw) {
    if (raw == null) return const [];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return const [];
      return data
          .map(SourceSubscription.tryFromJson)
          .whereType<SourceSubscription>()
          .toList();
    } on FormatException {
      return const [];
    }
  }

  String get dandanplayAppId {
    final saved = _prefs.getString(_dandanAppIdKey);
    if (saved != null && saved.isNotEmpty) return saved;
    final env = Platform.environment['PRAXINO_DANDAN_APP_ID'];
    if (env != null && env.isNotEmpty) return env;
    return _decodeBuilt(_builtDandanAppIdB64, _builtDandanAppId);
  }

  String get dandanplayAppSecret {
    final saved = _prefs.getString(_dandanSecretKey);
    if (saved != null && saved.isNotEmpty) return saved;
    final env = Platform.environment['PRAXINO_DANDAN_APP_SECRET'];
    if (env != null && env.isNotEmpty) return env;
    return _decodeBuilt(_builtDandanAppSecretB64, _builtDandanAppSecret);
  }

  /// Build-time secrets are base64 encoded by the release workflow. This is
  /// obfuscation, not a security boundary; it only keeps plain text out of the
  /// binary's strings.
  static String _decodeBuilt(String encoded, String fallback) {
    if (encoded.isEmpty) return fallback;
    try {
      return utf8.decode(base64Decode(encoded));
    } on FormatException {
      return '';
    }
  }

  Future<void> setDandanplayCredentials(String appId, String secret) async {
    await _prefs.setString(_dandanAppIdKey, appId);
    await _prefs.setString(_dandanSecretKey, secret);
  }

  String get openSubtitlesApiKey {
    final saved = _prefs.getString(_openApiKeyKey);
    if (saved != null && saved.isNotEmpty) return saved;
    return Platform.environment['PRAXINO_OPENSUBTITLES_API_KEY'] ?? '';
  }

  String get openSubtitlesUsername =>
      _prefs.getString(_openUsernameKey) ?? '';
  String get openSubtitlesPassword =>
      _prefs.getString(_openPasswordKey) ?? '';
  String get openSubtitlesToken => _prefs.getString(_openTokenKey) ?? '';

  Future<void> setOpenSubtitlesCredentials({
    required String apiKey,
    required String username,
    required String password,
    String? token,
  }) async {
    await _prefs.setString(_openApiKeyKey, apiKey);
    await _prefs.setString(_openUsernameKey, username);
    await _prefs.setString(_openPasswordKey, password);
    if (token != null && token.isNotEmpty) {
      await _prefs.setString(_openTokenKey, token);
    }
  }

  Future<void> setOpenSubtitlesToken(String? token) async {
    if (token == null || token.isEmpty) {
      await _prefs.remove(_openTokenKey);
    } else {
      await _prefs.setString(_openTokenKey, token);
    }
  }

  DanmakuMatchStore get danmakuMatches => DanmakuMatchStore(_prefs);

  List<ExtraSource> get extraSources {
    final raw = _prefs.getString(_extraSourcesKey);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(ExtraSource.tryFromJson)
          .whereType<ExtraSource>()
          .toList();
    } on FormatException {
      return const [];
    }
  }

  Future<void> saveExtraSources(List<ExtraSource> sources) => _prefs.setString(
        _extraSourcesKey,
        jsonEncode(sources.map((source) => source.toJson()).toList()),
      );

  List<OfflineJob> get offlineJobs {
    final raw = _prefs.getString(_offlineJobsKey);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(OfflineJob.tryFromJson)
          .whereType<OfflineJob>()
          .toList();
    } on FormatException {
      return const [];
    }
  }

  Future<void> saveOfflineJobs(List<OfflineJob> jobs) => _prefs.setString(
        _offlineJobsKey,
        jsonEncode(jobs.map((job) => job.toJson()).toList()),
      );

  String? get skippedUpdateVersion => _prefs.getString(_skippedUpdateKey);

  Future<void> setSkippedUpdateVersion(String? version) async {
    if (version == null || version.isEmpty) {
      await _prefs.remove(_skippedUpdateKey);
    } else {
      await _prefs.setString(_skippedUpdateKey, version);
    }
  }

  String? get offlineFfmpegPath => _prefs.getString(_offlineFfmpegKey);
  String? get offlineEsrganPath => _prefs.getString(_offlineEsrganKey);
  String? get offlineRifePath => _prefs.getString(_offlineRifeKey);

  Future<void> setOfflineToolPaths({
    String? ffmpeg,
    String? esrgan,
    String? rife,
  }) async {    Future<void> write(String key, String? value) async {
      if (value == null || value.trim().isEmpty) {
        await _prefs.remove(key);
      } else {
        await _prefs.setString(key, value.trim());
      }
    }

    await write(_offlineFfmpegKey, ffmpeg);
    await write(_offlineEsrganKey, esrgan);
    await write(_offlineRifeKey, rife);
  }

  String? get interpolationScriptPath => _prefs.getString(_vpyScriptKey);

  Future<void> setInterpolationScriptPath(String? path) async {
    if (path == null || path.trim().isEmpty) {
      await _prefs.remove(_vpyScriptKey);
    } else {
      await _prefs.setString(_vpyScriptKey, path.trim());
    }
  }
}
