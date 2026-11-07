import 'package:dio/dio.dart';

import 'user_agent.dart';

/// Owns the HTTP configuration used by every API and file request.
///
/// Streaming is handled by a separate native engine; consumers must pass
/// [mediaHeaders] when opening a media resource.
class NetworkClient {
  NetworkClient({Dio? dio, String? userAgent}) : dio = dio ?? Dio() {
    this.userAgent = userAgent ?? UserAgent.defaultValue;
    this.dio.options
      ..connectTimeout = const Duration(seconds: 12)
      ..receiveTimeout = const Duration(seconds: 25)
      ..sendTimeout = const Duration(seconds: 12)
      ..followRedirects = false
      ..validateStatus = (status) => status != null && status < 400;
  }

  final Dio dio;
  late String _userAgent;

  String get userAgent => _userAgent;

  set userAgent(String value) {
    final validated = UserAgent.validate(value);

    // Dio can retain a caller-supplied map with a narrow runtime value type
    // (for example, Map<String, List<String>>). Mutating it with a String
    // throws even though the public header API accepts dynamic values.
    // Replacing it with a properly typed copy avoids that runtime failure.
    final headers = <String, dynamic>{};
    for (final entry in dio.options.headers.entries) {
      if (entry.key.toLowerCase() != 'user-agent') {
        headers[entry.key] = entry.value;
      }
    }
    headers['user-agent'] = validated;
    dio.options.headers = headers;
    _userAgent = validated;
  }

  Map<String, String> get mediaHeaders => <String, String>{
    'User-Agent': _userAgent,
    'Accept': '*/*',
  };

  /// Returns a fresh snapshot for image requests initiated by Flutter.
  Map<String, String> get imageHeaders => <String, String>{
    'User-Agent': _userAgent,
  };

  void dispose() => dio.close(force: true);
}
