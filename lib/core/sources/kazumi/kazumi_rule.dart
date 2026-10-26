/// Kazumi's community rule format (https://github.com/Predidit/KazumiRules).
///
/// Only the fields Praxino uses are modelled; unknown fields are ignored so
/// newer rule revisions keep loading.
class KazumiRule {
  const KazumiRule({
    required this.name,
    required this.version,
    required this.baseUrl,
    this.searchUrl = '',
    this.searchList = '',
    this.searchName = '',
    this.searchResult = '',
    this.chapterRoads = '',
    this.chapterResult = '',
    this.userAgent = '',
    this.referer = '',
    this.usePost = false,
    this.useWebview = true,
    this.searchMode = 'xpath',
    this.chapterMode = 'xpath',
    this.searchApi,
    this.chapterApi,
  });

  final String name;
  final String version;
  final String baseUrl;
  final String searchUrl;
  final String searchList;
  final String searchName;
  final String searchResult;
  final String chapterRoads;
  final String chapterResult;
  final String userAgent;
  final String referer;
  final bool usePost;

  /// The play page needs a browser to reveal the stream URL.
  final bool useWebview;

  /// `xpath` or `api`.
  final String searchMode;
  final String chapterMode;
  final Map<String, dynamic>? searchApi;
  final Map<String, dynamic>? chapterApi;

  factory KazumiRule.fromJson(Map<String, dynamic> json) => KazumiRule(
        name: json['name'] as String,
        version: '${json['version'] ?? ''}',
        baseUrl: json['baseURL'] as String? ?? '',
        searchUrl: json['searchURL'] as String? ?? '',
        searchList: json['searchList'] as String? ?? '',
        searchName: json['searchName'] as String? ?? '',
        searchResult: json['searchResult'] as String? ?? '',
        chapterRoads: json['chapterRoads'] as String? ?? '',
        chapterResult: json['chapterResult'] as String? ?? '',
        userAgent: json['userAgent'] as String? ?? '',
        referer: json['referer'] as String? ?? '',
        usePost: json['usePost'] == true,
        useWebview: json['useWebview'] != false,
        searchMode: json['searchMode'] as String? ?? 'xpath',
        chapterMode: json['chapterMode'] as String? ?? 'xpath',
        searchApi: json['searchApiConfig'] as Map<String, dynamic>?,
        chapterApi: json['chapterApiConfig'] as Map<String, dynamic>?,
      );

  /// Parses either a single rule object or a list of them.
  static List<KazumiRule> parseAll(Object? json) => switch (json) {
        final List<dynamic> list => list
            .whereType<Map<String, dynamic>>()
            .map(KazumiRule.fromJson)
            .toList(),
        final Map<String, dynamic> one => [KazumiRule.fromJson(one)],
        _ => const [],
      };
}
