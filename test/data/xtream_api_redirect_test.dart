import 'package:denuczi_tv/core/errors/app_exception.dart';
import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/network/http_redirect_policy.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const httpAccount = AccountCredentials(
    serverUrl: 'http://provider.example',
    username: 'test-user',
    password: 'test-password',
    label: 'Fixture',
  );
  const httpsAccount = AccountCredentials(
    serverUrl: 'https://provider.example',
    username: 'test-user',
    password: 'test-password',
    label: 'Fixture',
  );
  final success = <String, Object?>{
    'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
  };

  test('preserves a redirect token without copying the source query', () async {
    final client = NetworkClient();
    addTearDown(client.dispose);
    final visited = <Uri>[];
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          visited.add(request.uri);
          final redirect = request.uri.scheme == 'http';
          handler.resolve(
            Response<Object?>(
              requestOptions: request,
              statusCode: redirect ? 302 : 200,
              headers: redirect
                  ? Headers.fromMap({
                      'location': [
                        'https://cdn.example/player_api.php?token=short-lived',
                      ],
                    })
                  : Headers(),
              data: redirect ? null : success,
            ),
          );
        },
      ),
    );
    expect(
      (await XtreamApi(client).authenticate(httpAccount)).authorized,
      isTrue,
    );
    expect(visited, hasLength(2));
    expect(visited.last.host, 'cdn.example');
    expect(visited.last.queryParameters, {'token': 'short-lived'});
    expect(visited.last.queryParameters.containsKey('password'), isFalse);
  });

  test('blocks HTTPS-to-HTTP API redirects by default', () async {
    final client = NetworkClient();
    addTearDown(client.dispose);
    var calls = 0;
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          calls++;
          handler.resolve(
            Response<Object?>(
              requestOptions: request,
              statusCode: 302,
              headers: Headers.fromMap({
                'location': ['http://cdn.example/player_api.php?token=test'],
              }),
            ),
          );
        },
      ),
    );
    await expectLater(
      XtreamApi(client).authenticate(httpsAccount),
      throwsA(isA<AppException>()),
    );
    expect(calls, 1);
  });

  test('allows an opted-in HTTPS-to-HTTP API redirect', () async {
    final client = NetworkClient()..allowHttpsToHttpRedirects = true;
    addTearDown(client.dispose);
    var calls = 0;
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          calls++;
          handler.resolve(
            Response<Object?>(
              requestOptions: request,
              statusCode: calls == 1 ? 307 : 200,
              headers: calls == 1
                  ? Headers.fromMap({
                      'location': [
                        'http://cdn.example/player_api.php?token=test',
                      ],
                    })
                  : Headers(),
              data: calls == 1 ? null : success,
            ),
          );
        },
      ),
    );
    expect(
      (await XtreamApi(client).authenticate(httpsAccount)).authorized,
      isTrue,
    );
    expect(calls, 2);
  });

  test('supports relative redirects without inheriting credentials', () {
    const policy = HttpRedirectPolicy();
    final next = policy.resolve(
      Uri.parse('https://example.org/player_api.php?username=u&password=p'),
      '/api/renew?token=abc',
    );
    expect(next.toString(), 'https://example.org/api/renew?token=abc');
  });

  test('rejects unsafe URLs and invalid headers', () {
    const policy = HttpRedirectPolicy(allowHttpsToHttpRedirect: true);
    final original = Uri.parse('https://provider.example/a');
    for (final location in <String>[
      'file:///etc/passwd',
      'ftp://provider.example/stream',
      'https://user:pass@cdn.example/a',
      'https://cdn.example/stream#fragment',
      '',
      'https://cdn.example/redirect\r\nExtra: value',
    ]) {
      expect(
        () => policy.resolve(original, location),
        throwsA(isA<AppException>()),
      );
    }
  });

  test('rejects API redirect loops', () async {
    final client = NetworkClient();
    addTearDown(client.dispose);
    var calls = 0;
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          calls++;
          handler.resolve(
            Response<Object?>(
              requestOptions: request,
              statusCode: 301,
              headers: Headers.fromMap({
                'location': [request.uri.toString()],
              }),
            ),
          );
        },
      ),
    );
    await expectLater(
      XtreamApi(client).authenticate(httpAccount),
      throwsA(isA<AppException>()),
    );
    expect(calls, 1);
  });

  test('enforces the four-hop API redirect limit', () async {
    final client = NetworkClient();
    addTearDown(client.dispose);
    var calls = 0;
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          calls++;
          handler.resolve(
            Response<Object?>(
              requestOptions: request,
              statusCode: 302,
              headers: Headers.fromMap({
                'location': ['https://provider.example/hop$calls'],
              }),
            ),
          );
        },
      ),
    );
    await expectLater(
      XtreamApi(client).authenticate(httpsAccount),
      throwsA(isA<AppException>()),
    );
    expect(calls, 5);
  });

  test('rejects credential headers on cross-origin redirects', () async {
    final client = NetworkClient();
    addTearDown(client.dispose);
    client.dio.options.headers['authorization'] = 'Bearer example';
    var calls = 0;
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          calls++;
          handler.resolve(
            Response<Object?>(
              requestOptions: request,
              statusCode: 302,
              headers: Headers.fromMap({
                'location': ['https://cdn.example/player_api.php'],
              }),
            ),
          );
        },
      ),
    );
    await expectLater(
      XtreamApi(client).authenticate(httpsAccount),
      throwsA(isA<AppException>()),
    );
    expect(calls, 1);
  });
}
