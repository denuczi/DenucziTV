import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/network_client.dart';

/// Resolves media redirects explicitly without forwarding account credentials.
///
/// Only the URL provided in each Location header is used for the next request.
/// No authorization headers, cookies, or original query parameters are copied.
/// The global User-Agent is retained and TLS verification remains enabled.
///
/// A separately persisted user preference can permit HTTPS-to-HTTP redirects
/// for downloads. It never disables TLS verification for HTTPS requests.
class DownloadHttpClient {
  const DownloadHttpClient(this._network);

  static const int maxRedirects = 4;
  static const Set<int> _redirectCodes = {301, 302, 303, 307, 308};

  final NetworkClient _network;

  Future<Response<ResponseBody>> open(
    Uri source, {
    required CancelToken cancelToken,
    bool allowHttpsToHttpRedirect = false,
    int startByte = 0,
    String? ifRange,
    int? endByte,
  }) async {
    if (startByte < 0 || (endByte != null && endByte < startByte)) {
      throw const AppException('Invalid download byte range.');
    }
    var current = source;
    final visited = <Uri>{};
    var redirects = 0;
    final redirectPolicy = DownloadRedirectPolicy(
      allowHttpsToHttpRedirect: allowHttpsToHttpRedirect,
    );

    // The desktop HTTP client normally only includes User-Agent. Reject a
    // modified transport with credentials rather than forwarding them to a CDN.
    const sensitiveHeaders = {'authorization', 'proxy-authorization', 'cookie'};
    if (_network.dio.options.headers.keys.any(
      (name) => sensitiveHeaders.contains(name.toLowerCase()),
    )) {
      throw const AppException(
        'Authenticated HTTP headers cannot be forwarded during a download.',
      );
    }

    while (true) {
      DownloadRedirectPolicy.validateTarget(current);
      if (!visited.add(current)) {
        throw const AppException('The provider returned a redirect loop.');
      }
      if (cancelToken.isCancelled) {
        throw const AppException('Download cancelled.');
      }

      final response = await _network.dio.getUri<ResponseBody>(
        current,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (status) =>
              status == 200 ||
              status == 206 ||
              (status != null && _redirectCodes.contains(status)),
          receiveTimeout: const Duration(seconds: 45),
          headers: {
            'User-Agent': _network.userAgent,
            'Accept-Encoding': 'identity',
            if (startByte > 0 || endByte != null)
              'Range': 'bytes=$startByte-${endByte ?? ''}',
            if (ifRange != null && ifRange.isNotEmpty) 'If-Range': ifRange,
          },
        ),
      );
      final code = response.statusCode;
      if (code == 200 || code == 206) {
        return response;
      }

      // Release the previous connection without waiting for a potentially
      // unbounded redirect body. Cancelling a take(1) subscription closes it.
      await response.data?.stream.take(1).drain<void>();
      if (redirects >= maxRedirects) {
        throw const AppException(
          'The provider exceeded the four-redirect limit.',
        );
      }
      final location = response.headers.value('location');
      if (location == null || location.trim().isEmpty) {
        throw const AppException(
          'The provider redirected without a Location header.',
        );
      }
      current = redirectPolicy.resolve(current, location);
      redirects++;
    }
  }
}

/// Resolves a single redirect according to the configured download policy.
///
/// Starting a download over HTTP is always allowed. Only a transition from
/// HTTPS to HTTP requires explicit user consent. The destination must come
/// from the server's Location header; previous URL credentials are not copied.
final class DownloadRedirectPolicy {
  const DownloadRedirectPolicy({this.allowHttpsToHttpRedirect = false});

  final bool allowHttpsToHttpRedirect;

  Uri resolve(Uri origin, String location) {
    final Uri next;
    try {
      next = origin.resolve(location.trim());
    } on FormatException {
      throw const AppException(
        'The provider supplied an invalid redirect URL.',
      );
    }
    validateTarget(next);
    if (origin.scheme == 'https' &&
        next.scheme == 'http' &&
        !allowHttpsToHttpRedirect) {
      throw const AppException(
        'The provider redirected from HTTPS to HTTP. To allow this download, '
        'enable "Allow HTTPS-to-HTTP download redirects" in Settings.',
      );
    }
    return next;
  }

  /// Restrict downloads to HTTP(S) URIs without embedded Basic-auth userinfo.
  static void validateTarget(Uri uri) {
    if ((uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const AppException('The provider supplied an unsafe download URL.');
    }
  }
}
