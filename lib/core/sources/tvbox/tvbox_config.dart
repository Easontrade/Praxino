import 'dart:convert';
import 'dart:io';

/// One plain HTTP site from a TVBox config.
class TvBoxSite {
  const TvBoxSite({
    required this.name,
    required this.api,
    required this.type,
    this.searchable = true,
  });

  final String name;
  final String api;
  final int type;
  final bool searchable;
}

class TvBoxConfigParser {
  TvBoxConfigParser._();

  /// Accepts a single config (sites) or a warehouse (urls).
  static List<TvBoxSite> sitesFromJson(Object? raw, {Uri? baseUri}) {
    if (raw is! Map) return const [];
    final sites = raw['sites'];
    if (sites is! List) return const [];
    final result = <TvBoxSite>[];
    final seen = <String>{};
    for (final item in sites) {
      if (item is! Map) continue;
      final type = int.tryParse('${item['type'] ?? ''}');
      if (type != 0 && type != 1) continue;
      final rawApi = item['api'];
      if (rawApi is! String || rawApi.trim().isEmpty) continue;
      var api = rawApi.trim();
      final uri = Uri.tryParse(api);
      if (uri != null && !uri.hasScheme && baseUri != null) {
        api = baseUri.resolve(api).toString();
      }
      if (!(api.startsWith('http://') || api.startsWith('https://'))) {
        continue;
      }
      if (!seen.add(api)) continue;
      final name = '${item['name'] ?? item['key'] ?? api}';
      result.add(TvBoxSite(
        name: name.isEmpty ? api : name,
        api: api,
        type: type!,
        searchable: item['searchable'] != 0,
      ));
    }
    return result;
  }

  static List<Uri> warehouseUrls(Object? raw) {
    if (raw is! Map) return const [];
    final urls = raw['urls'];
    if (urls is! List) return const [];
    return [
      for (final item in urls)
        if (item is Map && item['url'] is String)
          if (Uri.tryParse(item['url'] as String) case final uri?)
            if (uri.hasScheme) uri,
    ];
  }
}

/// Reads already-downloaded local TVBox configs; never fetches by itself.
class TvBoxConfigLoader {
  TvBoxConfigLoader._();

  static Future<List<TvBoxSite>> loadDirectory(Directory directory) async {
    if (!await directory.exists()) return const [];
    final result = <TvBoxSite>[];
    final seen = <String>{};
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
        continue;
      }
      try {
        final decoded = jsonDecode(
          utf8.decode(await entity.readAsBytes(), allowMalformed: true),
        );
        for (final site
            in TvBoxConfigParser.sitesFromJson(decoded, baseUri: entity.uri)) {
          if (seen.add(site.api)) result.add(site);
        }
      } on Object {
        // One broken/partial file must not hide the other configs.
      }
    }
    return result;
  }
}
