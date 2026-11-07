import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/errors/app_exception.dart';
import 'package:denuczi_tv/core/network/server_address.dart';

void main() {
  group('ServerAddress', () {
    test('preserves HTTPS and an optional base path', () {
      final base = ServerAddress.parse('https://tv.example:8443/xtream/');
      final api = ServerAddress.api(base, {
        'username': 'user',
        'password': 'abc&def',
      });
      expect(api.scheme, 'https');
      expect(api.port, 8443);
      expect(api.path, '/xtream/player_api.php');
      expect(api.queryParameters['password'], 'abc&def');
    });

    test('escapes credentials in the media path', () {
      final uri = ServerAddress.stream(
        ServerAddress.parse('https://tv.example'),
        type: 'movie',
        username: 'john/doe',
        password: 'p#ss word',
        streamId: '42',
        extension: 'mp4',
      );
      expect(uri.pathSegments, ['movie', 'john/doe', 'p#ss word', '42.mp4']);
      expect(uri.toString(), contains('john%2Fdoe'));
      expect(uri.toString(), contains('p%23ss%20word'));
    });

    test('rejects URL credentials and unsafe schemes', () {
      for (final input in [
        'file:///etc/passwd',
        'http://user:password@example.com',
        'https://example.com?password=secret',
        'javascript:alert(1)',
      ]) {
        expect(() => ServerAddress.parse(input), throwsA(isA<AppException>()));
      }
    });

    test('rejects unsupported media extensions', () {
      expect(
        () => ServerAddress.stream(
          ServerAddress.parse('https://tv.example'),
          type: 'live',
          username: 'user',
          password: 'pass',
          streamId: '10',
          extension: '../m3u8',
        ),
        throwsA(isA<AppException>()),
      );
    });
  });
}
