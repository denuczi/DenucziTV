import '../errors/app_exception.dart';

/// Validates a provider endpoint without silently downgrading HTTPS.
abstract final class ServerAddress {
  static Uri parse(String input) {
    final value = input.trim();
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const AppException('Enter an absolute HTTP or HTTPS server URL.');
    }
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (uri.pathSegments.any((segment) => segment == '..' || segment == '.')) {
      throw const AppException('Server URL contains an unsupported path.');
    }
    return uri.replace(path: path, query: null, fragment: null);
  }

  static Uri api(Uri base, Map<String, String> parameters) => base.replace(
    path: '${base.path}/player_api.php',
    queryParameters: parameters,
  );

  static Uri stream(
    Uri base, {
    required String type,
    required String username,
    required String password,
    required String streamId,
    required String extension,
  }) {
    if (!{'live', 'movie', 'series'}.contains(type) ||
        !RegExp(r'^[a-zA-Z0-9]+$').hasMatch(extension)) {
      throw const AppException('Unsupported stream format.');
    }
    final segments = <String>[
      ...base.pathSegments.where((segment) => segment.isNotEmpty),
      type,
      username,
      password,
      '$streamId.$extension',
    ];
    return base.replace(pathSegments: segments, query: null);
  }
}
