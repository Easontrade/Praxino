import 'webdav_client.dart';

/// A saved WebDAV / OpenList endpoint. Credentials stay in local settings.
class WebDavServer {
  const WebDavServer({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String username;
  final String password;

  WebDavClient client() => WebDavClient(
        baseUrl: baseUrl,
        username: username,
        password: password,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'username': username,
        'password': password,
      };

  static WebDavServer? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final baseUrl = raw['baseUrl'];
    if (id is! String || name is! String || baseUrl is! String) return null;
    return WebDavServer(
      id: id,
      name: name,
      baseUrl: baseUrl,
      username: raw['username'] is String ? raw['username'] as String : '',
      password: raw['password'] is String ? raw['password'] as String : '',
    );
  }
}
