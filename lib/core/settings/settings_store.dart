import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../enhance/enhance_settings.dart';

/// User preferences that outlive a single playback.
class SettingsStore {
  SettingsStore._(this._prefs);

  static Future<SettingsStore> load() async =>
      SettingsStore._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _enhanceKey = 'enhance.v1';
  static const _recentKey = 'recent.v1';
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
}
