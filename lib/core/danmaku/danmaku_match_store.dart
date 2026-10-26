import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the user's chosen dandanplay episode per show/episode key.
class DanmakuMatchStore {
  DanmakuMatchStore(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'danmaku.matches.v1';

  Map<String, int> get _all {
    final raw = _prefs.getString(_key);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is num) '${entry.key}': (entry.value as num).toInt(),
      };
    } on FormatException {
      return {};
    }
  }

  int? episodeFor(String showKey) => _all[showKey];

  Future<void> remember(String showKey, int episodeId) {
    final data = _all..[showKey] = episodeId;
    return _prefs.setString(_key, jsonEncode(data));
  }

  Future<void> forget(String showKey) {
    final data = _all..remove(showKey);
    return _prefs.setString(_key, jsonEncode(data));
  }
}
