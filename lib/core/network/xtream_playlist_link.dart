import '../errors/app_exception.dart';
import 'server_address.dart';

/// Extracts manual Xtream credentials from a complete get.php playlist URL.
/// Parsing is local: no link resolution or playlist request is performed.
abstract final class XtreamPlaylistLink {
  static ({String serverUrl, String username, String password})? tryParse(
    String input,
  ) {
    final value = input.trim();
    if (value.length > 8192 || value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      return null;
    }

    try {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasFragment ||
          !uri.path.endsWith('/get.php') ||
          uri.port <= 0 ||
          uri.port > 65535) {
        return null;
      }

      // Never turn an expiring protected destination into a manual account.
      // Duplicate fields are ambiguous; queryParametersAll preserves them.
      final parameters = uri.queryParametersAll;
      if (parameters.containsKey('dtv_expires')) {
        return null;
      }
      String? singleValue(String key) {
        final values = parameters[key];
        if (values == null ||
            values.length != 1 ||
            values.single.trim().isEmpty) {
          return null;
        }
        return values.single;
      }

      final username = singleValue('username');
      final password = singleValue('password');
      if (username == null || password == null) {
        return null;
      }

      // Preserve any provider base path and custom port. Never retain playlist
      // parameters (including credentials) in the visible server URL.
      final base = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: uri.path.substring(0, uri.path.length - '/get.php'.length),
      );
      return (
        serverUrl: ServerAddress.parse(base.toString()).toString(),
        username: username,
        password: password,
      );
    } on FormatException {
      return null;
    } on AppException {
      return null;
    }
  }
}
