import 'package:denuczi_tv/core/network/xtream_playlist_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('XtreamPlaylistLink', () {
    test('extracts credentials and retains a custom port', () {
      final link = XtreamPlaylistLink.tryParse(
        'http://provider.example:8880/get.php?username=demo-user&password=demo-pass&type=m3u_plus',
      );

      expect(link?.serverUrl, 'http://provider.example:8880');
      expect(link?.username, 'demo-user');
      expect(link?.password, 'demo-pass');
      expect(link?.serverUrl, isNot(contains('demo-pass')));
    });

    test('preserves HTTPS and the provider base path', () {
      final link = XtreamPlaylistLink.tryParse(
        'https://provider.example:8443/iptv/get.php?type=m3u_plus&username=user&password=secret&output=ts',
      );

      expect(link?.serverUrl, 'https://provider.example:8443/iptv');
      expect(link?.username, 'user');
      expect(link?.password, 'secret');
    });

    test('decodes encoded credentials exactly once', () {
      final link = XtreamPlaylistLink.tryParse(
        'https://provider.example/get.php?username=user%40name&password=p%26%3D%2B%23%252F',
      );

      expect(link?.username, 'user@name');
      expect(link?.password, 'p&=+#%2F');
      expect(link?.serverUrl, 'https://provider.example');
    });

    test('rejects missing or ambiguous credentials', () {
      for (final input in [
        'http://provider.example/get.php?username=user',
        'http://provider.example/get.php?password=secret',
        'http://provider.example/get.php?username=&password=secret',
        'http://provider.example/get.php?username=user&password=%20',
        'http://provider.example/get.php?username=first&username=second&password=secret',
        'http://provider.example/get.php?username=user&password=one&password=two',
        'https://provider.example/get.php?username=user&password=secret&dtv_expires=1999999999',
      ]) {
        expect(XtreamPlaylistLink.tryParse(input), isNull);
      }
    });

    test('does not interpret regular URLs or unexpected paths as playlists', () {
      for (final input in [
        'https://provider.example:8443',
        'https://provider.example:8443/iptv',
        'https://provider.example/player_api.php?username=user&password=secret',
        'https://provider.example/not-get.php?username=user&password=secret',
        'https://provider.example/get.php/',
        'https://provider.example/get.php',
      ]) {
        expect(XtreamPlaylistLink.tryParse(input), isNull);
      }
    });

    test('rejects invalid URL authorities and fragments', () {
      for (final input in [
        'file:///get.php?username=user&password=secret',
        'http://user:pass@provider.example/get.php?username=user&password=secret',
        'https://provider.example:999999/get.php?username=user&password=secret',
        'https://provider.example/get.php?username=user&password=secret#fragment',
        'https://provider.example/get.php?username=user&password=secret\nignored',
      ]) {
        expect(XtreamPlaylistLink.tryParse(input), isNull);
      }
    });
  });
}
