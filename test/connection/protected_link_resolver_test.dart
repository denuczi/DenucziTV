import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/errors/app_exception.dart';
import 'package:denuczi_tv/features/connection/data/protected_link_resolver.dart';

const origin = 'https://link.example/client/token';
const target =
    'http://provider.example:8080/get.php?username=user&password=secret';
const identifyingAgent =
    'DenucziTV/Test ProtectedLink/1 Installation/fake-identity';
const normalAgent = 'CustomPlayer/1';

Future<ResolvedProtectedLink> resolve(
  LinkRedirectRequest request, {
  String url = origin,
}) => ProtectedLinkResolver(request: request).resolve(
  originalUrl: url,
  label: 'Test',
  identificationUserAgent: identifyingAgent,
  genericUserAgent: normalAgent,
);

void main() {
  for (final code in [301, 302, 303, 307, 308]) {
    for (final scheme in ['http', 'https']) {
      test(
        '$code resolves $scheme without requesting the credential destination',
        () async {
          var requests = 0;
          final result = await resolve((uri, method, headers, timeout) async {
            requests++;
            expect(method, 'GET');
            expect(headers['User-Agent'], identifyingAgent);
            expect(uri.path, '/client/token');
            return LinkRedirectResponse(
              code,
              target.replaceFirst('http:', '$scheme:'),
            );
          }, url: origin.replaceFirst('https:', '$scheme:'));
          expect(requests, 1);
          expect(
            result.credentials.serverUrl,
            '$scheme://provider.example:8080',
          );
          expect(result.credentials.username, 'user');
          expect(result.credentials.password, 'secret');
          expect(result.expiresAt, isNull);
        },
      );
    }
  }

  test(
    'relative and cross-protocol hops never receive the installation UA',
    () async {
      final observed = <Uri>[];
      final result = await resolve((uri, method, headers, timeout) async {
        observed.add(uri);
        expect(
          headers.keys.map((key) => key.toLowerCase()),
          isNot(contains('authorization')),
        );
        expect(
          headers.keys.map((key) => key.toLowerCase()),
          isNot(contains('cookie')),
        );
        expect(
          headers['User-Agent'],
          observed.length == 1 ? identifyingAgent : normalAgent,
        );
        return switch (observed.length) {
          1 => const LinkRedirectResponse(302, '../next'),
          2 => const LinkRedirectResponse(307, 'http://other.example/hop'),
          _ => const LinkRedirectResponse(
            308,
            'https://provider.example/get.php?output=ts&password=p%26s&type=m3u_plus&username=a%2Bb&dtv_expires=4070908800',
          ),
        };
      });
      expect(observed[1].path, '/next');
      expect(observed[2].scheme, 'http');
      expect(result.credentials.username, 'a+b');
      expect(result.credentials.password, 'p&s');
      expect(result.credentials.serverUrl, 'https://provider.example');
      expect(result.expiresAt, DateTime.utc(2099));
      expect(result.credentials.serverUrl, isNot(contains('dtv_expires')));
    },
  );

  test('four redirects are accepted; a fifth is rejected', () async {
    for (final total in [4, 5]) {
      var calls = 0;
      final result = resolve((uri, method, headers, timeout) async {
        calls++;
        return LinkRedirectResponse(
          302,
          calls == total ? target : 'https://link.example/hop/$calls',
        );
      });
      if (total == 4) {
        expect((await result).credentials.username, 'user');
      } else {
        await expectLater(result, throwsA(isA<AppException>()));
      }
      expect(calls, total);
    }
  });

  test('loops and missing redirect locations fail safely', () async {
    await expectLater(
      resolve(
        (uri, method, headers, timeout) async =>
            const LinkRedirectResponse(302, origin),
      ),
      throwsA(isA<AppException>()),
    );
    await expectLater(
      resolve(
        (uri, method, headers, timeout) async =>
            const LinkRedirectResponse(302, null),
      ),
      throwsA(isA<AppException>()),
    );
  });

  for (final query in [
    'username=&password=p',
    'username=u&password=',
    'username=u',
    'username=u&username=v&password=p',
    'username=u&password=p&dtv_expires=invalid',
    'username=u&password=p&dtv_expires=-1',
    'username=u&password=p&dtv_expires=0',
    'username=u&password=p&dtv_expires=4070908800000',
  ]) {
    test('rejects malformed credential/expiry parameters: $query', () async {
      await expectLater(
        resolve(
          (uri, method, headers, timeout) async => LinkRedirectResponse(
            302,
            'https://provider.example/get.php?$query',
          ),
        ),
        throwsA(isA<AppException>()),
      );
    });
  }

  for (final url in [
    'not-a-url',
    'file:///tmp/example',
    'ftp://link.example/a',
    'https://user:password@link.example/a',
    'https://link.example/a#fragment',
    'https://link.example:99999/a',
  ]) {
    test(
      'rejects malformed permanent URL without contacting a server: $url',
      () {
        expect(
          () => ProtectedLinkResolver.validateUrl(url),
          throwsA(isA<AppException>()),
        );
      },
    );
  }

  for (final status in [404, 500, 502, 503, 401, 403]) {
    test('HTTP $status does not fall back to a playlist download', () async {
      var calls = 0;
      await expectLater(
        resolve((uri, method, headers, timeout) async {
          calls++;
          return LinkRedirectResponse(status, null);
        }),
        throwsA(isA<AppException>()),
      );
      expect(calls, 1);
    });
  }

  test(
    'GET probes request a minimal range without following get.php',
    () async {
      var calls = 0;
      await resolve((uri, method, headers, timeout) async {
        calls++;
        expect(method, 'GET');
        expect(headers['Range'], 'bytes=0-0');
        return const LinkRedirectResponse(302, target);
      });
      expect(calls, 1);
    },
  );

  test('DNS and timeout failures do not expose URLs or identifiers', () async {
    for (final failure in [
      const SocketException('secret.example'),
      TimeoutException(identifyingAgent),
    ]) {
      try {
        await resolve((uri, method, headers, timeout) => Future.error(failure));
        fail('Expected safe failure');
      } on AppException catch (error) {
        expect(error.message, isNot(contains('secret.example')));
        expect(error.message, isNot(contains(identifyingAgent)));
        expect(error.message, isNot(contains('token')));
      }
    }
  });

  test(
    'real HTTP transport inspects redirects without requesting a playlist',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var playlistRequests = 0;
      server.listen((request) {
        if (request.uri.path == '/get.php') playlistRequests++;
        request.response.statusCode = 302;
        request.response.headers.set(
          'location',
          '/get.php?username=user&password=secret',
        );
        unawaited(request.response.close().catchError((Object _) {}));
      });
      final result = await ProtectedLinkResolver().resolve(
        originalUrl: 'http://127.0.0.1:${server.port}/permanent',
        label: 'Local test',
        identificationUserAgent: identifyingAgent,
        genericUserAgent: normalAgent,
      );
      expect(result.credentials.serverUrl, 'http://127.0.0.1:${server.port}');
      expect(playlistRequests, 0);
    },
  );
}
