import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/errors/app_exception.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/network/user_agent.dart';

void main() {
  group('NetworkClient User-Agent', () {
    test('sets the configured User-Agent on the Dio client', () {
      final client = NetworkClient(userAgent: 'DesktopTest/1.0');
      addTearDown(client.dispose);

      expect(client.dio.options.headers['user-agent'], 'DesktopTest/1.0');
      expect(client.mediaHeaders['User-Agent'], 'DesktopTest/1.0');
      expect(client.imageHeaders['User-Agent'], 'DesktopTest/1.0');
    });

    test('normalizes existing header names when updating the preference', () {
      final dio = Dio(BaseOptions(headers: {'User-Agent': 'LegacyClient/1.0'}));
      final client = NetworkClient(dio: dio);
      addTearDown(client.dispose);

      expect(
        dio.options.headers.keys.where(
          (name) => name.toLowerCase() == 'user-agent',
        ),
        hasLength(1),
      );
      expect(dio.options.headers['user-agent'], UserAgent.defaultValue);

      client.userAgent = 'DesktopTest/2.0';
      expect(dio.options.headers['user-agent'], 'DesktopTest/2.0');
      expect(client.mediaHeaders['User-Agent'], 'DesktopTest/2.0');
      expect(client.imageHeaders['User-Agent'], 'DesktopTest/2.0');
    });

    test(
      'replaces a narrowly typed header map without losing other headers',
      () {
        final dio = Dio(
          BaseOptions(
            headers: <String, List<String>>{
              'User-Agent': ['LegacyClient/1.0'],
              'X-Trace': ['trace-1'],
            },
          ),
        );
        final client = NetworkClient(dio: dio);
        addTearDown(client.dispose);

        expect(dio.options.headers['user-agent'], UserAgent.defaultValue);
        expect(
          dio.options.headers.entries
              .singleWhere((entry) => entry.key.toLowerCase() == 'x-trace')
              .value,
          ['trace-1'],
        );

        client.userAgent = 'DesktopTest/3.0';
        expect(dio.options.headers['user-agent'], 'DesktopTest/3.0');
        expect(
          dio.options.headers.entries
              .singleWhere((entry) => entry.key.toLowerCase() == 'x-trace')
              .value,
          ['trace-1'],
        );
        expect(
          dio.options.headers.keys.where(
            (key) => key.toLowerCase() == 'user-agent',
          ),
          hasLength(1),
        );
      },
    );

    test('rejects invalid values without changing active headers', () {
      final client = NetworkClient(userAgent: 'DesktopTest/1.0');
      addTearDown(client.dispose);

      expect(
        () => client.userAgent = 'Injected\r\nHeader: malicious',
        throwsA(isA<AppException>()),
      );
      expect(client.userAgent, 'DesktopTest/1.0');
      expect(client.dio.options.headers['user-agent'], 'DesktopTest/1.0');
    });
  });
}
