import '../errors/app_exception.dart';

/// Validates the Location of an explicit Xtream API redirect.
///
/// The destination supplies its own query, which may contain a short-lived
/// token. Never append the account credentials from the original URL.
final class HttpRedirectPolicy {
  const HttpRedirectPolicy({this.allowHttpsToHttpRedirect = false});

  static const maxRedirects = 4;
  static const redirectCodes = <int>{301, 302, 303, 307, 308};
  static final _controlCharacters = RegExp(r'[\x00-\x1f\x7f]');

  final bool allowHttpsToHttpRedirect;

  Uri resolve(Uri source, String location) {
    final target = location.trim();
    if (target.isEmpty ||
        target.length > 8192 ||
        _controlCharacters.hasMatch(location)) {
      throw const AppException(
        'The provider supplied an invalid API redirect.',
      );
    }

    final Uri resolved;
    try {
      resolved = source.resolve(target);
      resolved.port;
    } on FormatException {
      throw const AppException(
        'The provider supplied an invalid API redirect.',
      );
    }
    if ((resolved.scheme != 'http' && resolved.scheme != 'https') ||
        resolved.host.isEmpty ||
        resolved.userInfo.isNotEmpty ||
        resolved.hasFragment ||
        resolved.port < 1 ||
        resolved.port > 65535) {
      throw const AppException('The provider supplied an unsafe API redirect.');
    }
    if (source.scheme == 'https' &&
        resolved.scheme == 'http' &&
        !allowHttpsToHttpRedirect) {
      throw const AppException(
        'The provider redirected the API from HTTPS to HTTP. '
        'Enable HTTPS-to-HTTP redirects in Settings to allow this connection.',
      );
    }
    return resolved;
  }
}
