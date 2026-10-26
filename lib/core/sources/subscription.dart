import 'dart:convert';

import 'package:http/http.dart' as http;

import 'kazumi/kazumi_rule.dart';
import 'kazumi/kazumi_rule_adapter.dart';
import 'source_adapter.dart';

/// A user-added subscription URL plus the rules downloaded from it.
///
/// Praxino ships no subscriptions. The user adds one at runtime; the parsed
/// rules are cached here so the source list survives restarts.
class SourceSubscription {
  const SourceSubscription({
    required this.url,
    this.name = '',
    this.enabled = true,
    this.etag,
    this.fetchedAt,
    this.rules = const [],
  });

  final String url;
  final String name;
  final bool enabled;
  final String? etag;
  final DateTime? fetchedAt;

  /// Raw rule objects, kept as JSON so the cache does not depend on the
  /// adapter's model.
  final List<Map<String, Object?>> rules;

  SourceSubscription copyWith({
    String? name,
    bool? enabled,
    String? etag,
    DateTime? fetchedAt,
    List<Map<String, Object?>>? rules,
  }) =>
      SourceSubscription(
        url: url,
        name: name ?? this.name,
        enabled: enabled ?? this.enabled,
        etag: etag ?? this.etag,
        fetchedAt: fetchedAt ?? this.fetchedAt,
        rules: rules ?? this.rules,
      );

  /// Builds the adapters this subscription provides.
  List<SourceAdapter> toAdapters({http.Client? client}) => [
        for (final rule in KazumiRule.parseAll(rules))
          KazumiRuleAdapter(rule, client: client),
      ];

  /// Builds a subscription from JSON the user pasted, without a network fetch.
  factory SourceSubscription.fromJsonText(String text, {String name = '本地规则'}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (error) {
      throw SubscriptionException('不是合法 JSON：${error.message}');
    }
    final rules = SubscriptionParser.parseRules(decoded);
    return SourceSubscription(
      url: 'local://${DateTime.now().microsecondsSinceEpoch}',
      name: name.isEmpty ? '本地规则' : name,
      fetchedAt: DateTime.now(),
      rules: rules,
    );
  }

  Map<String, Object?> toJson() => {
        'url': url,
        'name': name,
        'enabled': enabled,
        if (etag != null) 'etag': etag,
        if (fetchedAt != null) 'fetchedAt': fetchedAt!.toIso8601String(),
        'rules': rules,
      };

  static SourceSubscription? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final url = json['url'];
    if (url is! String || url.isEmpty) return null;
    final rawRules = json['rules'];
    final rules = <Map<String, Object?>>[];
    if (rawRules is List) {
      for (final rule in rawRules) {
        if (rule is Map) rules.add(Map<String, Object?>.from(rule));
      }
    }
    return SourceSubscription(
      url: url,
      name: json['name'] is String ? json['name'] as String : '',
      enabled: json['enabled'] != false,
      etag: json['etag'] is String ? json['etag'] as String : null,
      fetchedAt: json['fetchedAt'] is String
          ? DateTime.tryParse(json['fetchedAt'] as String)
          : null,
      rules: rules,
    );
  }
}

/// Fetches a subscription with conditional GET (ETag) and validates its rules.
class SubscriptionFetcher {
  SubscriptionFetcher({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 20);

  Future<SourceSubscription> fetch(SourceSubscription current) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      if (current.etag != null) 'If-None-Match': current.etag!,
    };
    final http.Response response;
    try {
      response = await _client
          .get(Uri.parse(current.url), headers: headers)
          .timeout(_timeout);
    } on Exception catch (error) {
      throw SubscriptionException('下载订阅失败：$error');
    }

    if (response.statusCode == 304) {
      return current.copyWith(fetchedAt: DateTime.now());
    }
    if (response.statusCode >= 400) {
      throw SubscriptionException('订阅返回 HTTP ${response.statusCode}');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (error) {
      throw SubscriptionException('订阅不是合法 JSON：${error.message}');
    }

    final rules = SubscriptionParser.parseRules(decoded);
    return current.copyWith(
      name: current.name.isEmpty ? _nameFor(current.url) : current.name,
      etag: response.headers['etag'],
      fetchedAt: DateTime.now(),
      rules: rules,
    );
  }

  /// Accepts a bare rule array or `{"rules": [...]}`; unknown/empty entries
  /// are skipped so one bad rule does not reject the whole subscription.
  static String _nameFor(String url) =>
      Uri.tryParse(url)?.host ?? '订阅';
}

/// Shared rule-list parsing for downloaded and pasted subscriptions.
class SubscriptionParser {
  SubscriptionParser._();

  /// Accepts a bare rule array, a single rule object, or `{"rules": [...]}`;
  /// unknown/empty entries are skipped so one bad rule does not reject the
  /// whole subscription.
  static List<Map<String, Object?>> parseRules(Object? decoded) {
    final Object? raw;
    if (decoded is Map && decoded['rules'] is List) {
      raw = decoded['rules'];
    } else if (decoded is Map) {
      raw = [decoded];
    } else {
      raw = decoded;
    }
    if (raw is! List) {
      throw const SubscriptionException('订阅必须是规则数组或单个规则对象');
    }
    final rules = <Map<String, Object?>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final rule = Map<String, Object?>.from(item);
      if (rule['name'] is String && (rule['name'] as String).isNotEmpty) {
        rules.add(rule);
      }
    }
    if (rules.isEmpty) throw const SubscriptionException('订阅里没有可用规则');
    return rules;
  }
}

class SubscriptionException implements Exception {
  const SubscriptionException(this.message);

  final String message;

  @override
  String toString() => message;
}
