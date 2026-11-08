import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/features/updates/data/github_release_api.dart';
import 'package:denuczi_tv/features/updates/domain/stable_release.dart';

import 'update_fixtures.dart';

void respond(
  RequestOptions options,
  RequestInterceptorHandler handler,
  Object? data, {
  int code = 200,
}) {
  handler.resolve(
    Response<ResponseBody>(
      requestOptions: options,
      statusCode: code,
      data: ResponseBody.fromString(jsonEncode(data), code),
    ),
  );
}

void main() {
  test('uses independent public headers, fixed pagination URLs and no account credentials', () async {
    final dio = Dio(
      BaseOptions(
        headers: {
          'Authorization': 'IPTV_SECRET',
          'User-Agent': 'ProtectedLink Installation/secret',
          'Cookie': 'private',
        },
      ),
    );
    final api = GitHubReleaseApi(client: dio);
    addTearDown(api.dispose);
    var count = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          count++;
          expect(options.uri.host, 'api.github.com');
          expect(options.uri.path, '/repos/denuczi/DenucziTV/releases');
          expect(options.followRedirects, isFalse);
          expect(options.queryParameters, {'per_page': 100, 'page': count});
          final headers = options.headers.map(
            (key, value) => MapEntry(key.toLowerCase(), value),
          );
          expect(headers['user-agent'], 'DenucziTV-UpdateChecker/1');
          expect(headers, isNot(contains('authorization')));
          expect(headers, isNot(contains('cookie')));
          expect(headers.values.join(' '), isNot(contains('Installation/')));
          respond(
            options,
            handler,
            count == 1
                ? List.generate(
                    100,
                    (_) => releaseFixture('v99.0.0', prerelease: true),
                  )
                : [releaseFixture('v9.0.0')],
          );
        },
      ),
    );
    final releases = await api.fetch(CancelToken());
    expect(releases.single.version.canonical, '9.0.0');
    expect(count, 2);
  });

  for (final code in [403, 404, 429, 500, 502, 503, 302]) {
    test(
      'HTTP $code is retryable feedback, never a successful no-release result',
      () async {
        final dio = Dio();
        final api = GitHubReleaseApi(client: dio);
        addTearDown(api.dispose);
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) =>
                respond(options, handler, {}, code: code),
          ),
        );
        await expectLater(
          api.fetch(CancelToken()),
          throwsA(
            isA<UpdateRequestFailure>().having(
              (e) => e.status,
              'status',
              code == 403 || code == 429
                  ? UpdateStatus.rateLimited
                  : UpdateStatus.serverError,
            ),
          ),
        );
      },
    );
  }

  test('a public release list containing only prereleases is a successful empty stable list', () async {
    final dio = Dio();
    final api = GitHubReleaseApi(client: dio);
    addTearDown(api.dispose);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => respond(options, handler, [
          releaseFixture('v9.0.0', prerelease: true),
        ]),
      ),
    );
    expect(await api.fetch(CancelToken()), isEmpty);
  });

  for (final type in [
    DioExceptionType.connectionError,
    DioExceptionType.connectionTimeout,
    DioExceptionType.receiveTimeout,
  ]) {
    test('sanitises $type without returning raw network errors', () async {
      final dio = Dio();
      final api = GitHubReleaseApi(client: dio);
      addTearDown(api.dispose);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(
              requestOptions: options,
              type: type,
              error: const SocketException('Sensitive diagnostics'),
            ),
          ),
        ),
      );
      await expectLater(
        api.fetch(CancelToken()),
        throwsA(
          isA<UpdateRequestFailure>().having(
            (e) => e.status,
            'status',
            type == DioExceptionType.connectionError
                ? UpdateStatus.offline
                : UpdateStatus.timedOut,
          ),
        ),
      );
    });
  }

  for (final malformed in [
    'not json',
    '{}',
    '[null]',
    '[{"draft":false,"prerelease":false}]',
  ]) {
    test('rejects invalid response $malformed', () async {
      final dio = Dio();
      final api = GitHubReleaseApi(client: dio);
      addTearDown(api.dispose);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<ResponseBody>(
              requestOptions: options,
              statusCode: 200,
              data: ResponseBody.fromString(malformed, 200),
            ),
          ),
        ),
      );
      await expectLater(
        api.fetch(CancelToken()),
        throwsA(
          isA<UpdateRequestFailure>().having(
            (e) => e.status,
            'status',
            UpdateStatus.invalidResponse,
          ),
        ),
      );
    });
  }

  test('bounds streamed response bytes even without Content-Length', () async {
    final dio = Dio();
    final api = GitHubReleaseApi(client: dio);
    addTearDown(api.dispose);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response<ResponseBody>(
            requestOptions: options,
            statusCode: 200,
            data: ResponseBody(
              Stream.value(Uint8List(GitHubReleaseApi.maxPageBytes + 1)),
              200,
            ),
          ),
        ),
      ),
    );
    await expectLater(
      api.fetch(CancelToken()),
      throwsA(
        isA<UpdateRequestFailure>().having(
          (e) => e.status,
          'status',
          UpdateStatus.invalidResponse,
        ),
      ),
    );
  });

  test('exhausted pagination is an error instead of selecting from incomplete history', () async {
    final dio = Dio();
    final api = GitHubReleaseApi(client: dio);
    addTearDown(api.dispose);
    var requests = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests++;
          respond(
            options,
            handler,
            List.generate(100, (_) => releaseFixture('v9.0.0', draft: true)),
          );
        },
      ),
    );
    await expectLater(
      api.fetch(CancelToken()),
      throwsA(isA<UpdateRequestFailure>()),
    );
    expect(requests, GitHubReleaseApi.maxPages);
  });
  test(
    'download verification rechecks the exact tag and its current stable flag',
    () async {
      final dio = Dio();
      final api = GitHubReleaseApi(client: dio);
      addTearDown(api.dispose);
      var withdrawn = false;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.uri.pathSegments.last, 'v9.0.0+2');
            expect(
              options.uri.pathSegments.take(5).join('/'),
              'repos/denuczi/DenucziTV/releases/tags',
            );
            respond(
              options,
              handler,
              releaseFixture('v9.0.0+2', prerelease: withdrawn),
            );
          },
        ),
      );
      expect(await api.verifyRelease('v9.0.0+2', CancelToken()), isNotNull);
      withdrawn = true;
      expect(await api.verifyRelease('v9.0.0+2', CancelToken()), isNull);
    },
  );
}
