import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/errors/app_exception.dart';
import 'package:denuczi_tv/features/downloads/data/download_http_client.dart';

void main() {
  const secureByDefault = DownloadRedirectPolicy();
  const optionalDowngrade = DownloadRedirectPolicy(
    allowHttpsToHttpRedirect: true,
  );

  test('direct HTTP and ordinary HTTP redirects are unaffected', () {
    final origin = Uri.parse('http://provider.example/movie/1.mp4');
    expect(
      secureByDefault.resolve(origin, '/cdn/1.mp4').toString(),
      'http://provider.example/cdn/1.mp4',
    );
    expect(
      secureByDefault.resolve(origin, 'https://cdn.example/video.mp4').scheme,
      'https',
    );
  });

  test('HTTPS to HTTP is rejected without explicit opt-in', () {
    expect(
      () => secureByDefault.resolve(
        Uri.parse('https://provider.example/movie.mp4'),
        'http://provider.example/movie.mp4',
      ),
      throwsA(isA<AppException>()),
    );
  });

  test('HTTPS to HTTP is allowed when explicitly enabled', () {
    expect(
      optionalDowngrade
          .resolve(
            Uri.parse('https://provider.example/movie.mp4'),
            'http://cdn.example/video.mp4?ticket=123',
          )
          .toString(),
      'http://cdn.example/video.mp4?ticket=123',
    );
  });

  test('HTTPS to HTTPS works with either preference', () {
    expect(
      secureByDefault
          .resolve(
            Uri.parse('https://provider.example/movie.mp4'),
            'https://cdn.example/video.mp4',
          )
          .scheme,
      'https',
    );
  });

  test('non-HTTP protocols and URL userinfo are always rejected', () {
    final origin = Uri.parse('https://provider.example/movie.mp4');
    for (final location in <String>[
      'file:///tmp/video.mp4',
      'ftp://cdn.example/video.mp4',
      'http://user:password@cdn.example/video.mp4',
    ]) {
      expect(
        () => optionalDowngrade.resolve(origin, location),
        throwsA(isA<AppException>()),
      );
    }
  });

  test('redirect to another host does not inherit the source query', () {
    final result = optionalDowngrade.resolve(
      Uri.parse('https://provider.example/video.mp4?username=x&password=y'),
      'http://cdn.example/video.mp4?ticket=abc',
    );
    expect(result.host, 'cdn.example');
    expect(result.query, 'ticket=abc');
    expect(result.toString(), isNot(contains('password=y')));
  });
}
