import 'dart:async';
import 'dart:io';

import '../../../core/errors/app_exception.dart';
import '../../../core/models/account.dart';
import '../../../core/network/server_address.dart';

class LinkRedirectResponse {
  const LinkRedirectResponse(this.status, this.location);
  final int status;
  final String? location;
}

typedef LinkRedirectRequest = Future<LinkRedirectResponse> Function(
  Uri uri,
  String method,
  Map<String, String> headers,
  Duration timeout,
);

/// Each probe has a fresh cookie-free transport. Responses are closed after
/// their headers: no body is buffered, decoded, or drained, including servers that ignore Range.
Future<LinkRedirectResponse> requestLinkHeaders(
  Uri uri,
  String method,
  Map<String, String> headers,
  Duration timeout,
) async {
  final client = HttpClient()..connectionTimeout = timeout;
  final deadline = Timer(timeout, () => client.close(force: true));
  try {
    final request = await client.openUrl(method, uri).timeout(timeout);
    request.followRedirects = false;
    request.persistentConnection = false;
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(timeout);
    return LinkRedirectResponse(
      response.statusCode,
      response.headers.value(HttpHeaders.locationHeader),
    );
  } finally {
    deadline.cancel();
    client.close(force: true);
  }
}

class ResolvedProtectedLink {
  const ResolvedProtectedLink(this.credentials, this.expiresAt);
  final AccountCredentials credentials;
  final DateTime? expiresAt;
}

/// Resolves redirections only. The get.php destination is parsed, never requested.
class ProtectedLinkResolver {
  ProtectedLinkResolver({LinkRedirectRequest? request})
    : _request = request ?? requestLinkHeaders;
  final LinkRedirectRequest _request;
  static const redirectCodes = {301, 302, 303, 307, 308};

  static Uri validateUrl(String value) {
    Uri? uri;
    try {
      uri = Uri.tryParse(value.trim());
      if (uri != null) {
        uri.port;
      }
    } on FormatException {
      throw const AppException('Enter a valid protected HTTP or HTTPS link.');
    }
    if (value.length > 8192 ||
        value.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.port <= 0 ||
        uri.port > 65535) {
      throw const AppException('Enter a valid protected HTTP or HTTPS link.');
    }
    return uri;
  }

  static ResolvedProtectedLink parseTarget(Uri uri, String label) {
    if (!uri.path.endsWith('/get.php')) {
      throw const AppException(
        'The protected link returned an invalid Xtream destination.',
      );
    }
    final query = uri.queryParametersAll;
    String single(String key) {
      final values = query[key];
      if (values == null ||
          values.length != 1 ||
          values.single.trim().isEmpty) {
        throw const AppException(
          'The protected link returned an invalid Xtream destination.',
        );
      }
      return values.single;
    }

    final username = single('username');
    final password = single('password');
    DateTime? expires;
    if (query.containsKey('dtv_expires')) {
      final value = single('dtv_expires');
      final seconds = RegExp(r'^[0-9]+$').hasMatch(value)
          ? int.tryParse(value)
          : null;
      if (seconds == null || seconds <= 0 || seconds > 253402300799) {
        throw const AppException(
          'The protected link returned an invalid expiration.',
        );
      }
      expires = DateTime.fromMillisecondsSinceEpoch(
        seconds * 1000,
        isUtc: true,
      );
    }
    final base = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path.substring(0, uri.path.length - '/get.php'.length),
    );
    return ResolvedProtectedLink(
      AccountCredentials(
        serverUrl: ServerAddress.parse(base.toString()).toString(),
        username: username,
        password: password,
        label: label,
        protected: true,
        linkExpiresAt: expires,
      ),
      expires,
    );
  }

  Future<ResolvedProtectedLink> resolve({
    required String originalUrl,
    required String label,
    required String identificationUserAgent,
    required String genericUserAgent,
  }) async {
    var current = validateUrl(originalUrl);
    final visited = <Uri>{};
    final elapsed = Stopwatch()..start();
    var hops = 0;
    try {
      while (true) {
        if (!visited.add(current)) {
          throw const AppException(
            'The protected link contains a redirect loop.',
          );
        }
        // Never send identification or any request to a credential destination.
        if (current.path.endsWith('/get.php')) {
          if (hops == 0) {
            throw const AppException(
              'Enter a permanent protected link, not an Xtream destination.',
            );
          }
          return parseTarget(current, label);
        }
        Future<LinkRedirectResponse> probe(
          String method,
          Map<String, String> headers,
        ) {
          final remaining = const Duration(seconds: 40) - elapsed.elapsed;
          if (remaining <= Duration.zero) {
            throw TimeoutException('Protected link timeout');
          }
          final timeout = remaining < const Duration(seconds: 10)
              ? remaining
              : const Duration(seconds: 10);
          return _request(current, method, headers, timeout).timeout(timeout);
        }

        final headers = <String, String>{
          'User-Agent': hops == 0 ? identificationUserAgent : genericUserAgent,
          'Accept': '*/*',
        };
        // GET is compatible with link endpoints that do not implement HEAD.
        // Range is advisory; requestLinkHeaders closes the connection after
        // headers even when a server ignores it. No playlist body is consumed.
        final response = await probe('GET', {...headers, 'Range': 'bytes=0-0'});
        if (!redirectCodes.contains(response.status)) {
          if (response.status == 404) {
            throw const AppException('The protected link was not found.');
          }
          if (response.status == 401 || response.status == 403) {
            throw const AppException(
              'Access to the protected link was denied.',
            );
          }
          throw const AppException(
            'The protected link is unavailable or did not redirect.',
          );
        }
        if (hops >= 4) {
          throw const AppException(
            'The protected link exceeded four redirects.',
          );
        }
        final location = response.location;
        if (location == null ||
            location.trim().isEmpty ||
            location.length > 8192 ||
            location.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
          throw const AppException(
            'The protected link returned an invalid redirect.',
          );
        }
        current = validateUrl(current.resolve(location).toString());
        hops++;
      }
    } on AppException {
      rethrow;
    } on TimeoutException {
      throw const AppException('The protected link check timed out.');
    } catch (_) {
      throw const AppException(
        'Could not contact the protected link securely.',
      );
    }
  }
}
