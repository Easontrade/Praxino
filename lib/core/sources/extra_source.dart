enum ExtraSourceType { stremio, script }

/// A user-added source that is not a Kazumi/TVBox subscription.
class ExtraSource {
  const ExtraSource({
    required this.id,
    required this.name,
    required this.type,
    required this.location,
    this.enabled = true,
  });

  final String id;
  final String name;
  final ExtraSourceType type;

  /// Addon base URL for Stremio, or the JS text for a script source.
  final String location;
  final bool enabled;

  ExtraSource copyWith({bool? enabled, String? name}) => ExtraSource(
        id: id,
        name: name ?? this.name,
        type: type,
        location: location,
        enabled: enabled ?? this.enabled,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'location': location,
        'enabled': enabled,
      };

  static ExtraSource? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final type = raw['type'];
    final location = raw['location'];
    if (id is! String || name is! String || type is! String || location is! String) {
      return null;
    }
    final parsed = ExtraSourceType.values
        .where((candidate) => candidate.name == type)
        .firstOrNull;
    if (parsed == null) return null;
    return ExtraSource(
      id: id,
      name: name,
      type: parsed,
      location: location,
      enabled: raw['enabled'] != false,
    );
  }
}
