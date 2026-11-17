import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/m3u/domain/m3u_playlist.dart';

void main() {
  const parser = M3uPlaylistParser();

  test('parses optional metadata and a plain HTTP stream', () {
    final playlist = parser.parse('''#EXTM3U
#EXTINF:-1 tvg-id="example" tvg-name="News" tvg-logo="https://example.org/logo.png" group-title="General",News HD
https://media.example.org/live.m3u8
#EXTINF:-1,Untitled channel
https://media.example.org/live2.ts
''');
    expect(playlist.entries, hasLength(2));
    expect(playlist.entries.first.kind, LibraryKind.live);
    expect(playlist.entries.first.title, 'News HD');
    expect(playlist.entries.first.categoryId, 'General');
    expect(playlist.entries.first.channelNumber, 1);
    expect(playlist.entries.last.channelNumber, 2);
    expect(playlist.streamFor(playlist.entries.first.id)?.headers, isEmpty);
  });

  test('accepts an Extended M3U header with playlist attributes', () {
    final playlist = parser.parse(
      '''#EXTM3U url-tvg="https://example.org/epg.xml"
#EXTINF:-1,News
https://media.example.org/news.m3u8
''',
    );
    expect(playlist.entries.single.title, 'News');
  });

  test('same URL with different access headers remains separate', () {
    final playlist = parser.parse('''#EXTM3U
#EXTINF:-1,First
https://media.example.org/live.m3u8|origin=https://one.example
#EXTINF:-1,Second
https://media.example.org/live.m3u8|origin=https://two.example
''');
    expect(playlist.entries, hasLength(2));
    expect(playlist.entries[0].id, isNot(playlist.entries[1].id));
  });

  test('supports ampersand-separated, case-insensitive pipe headers', () {
    final playlist = parser.parse('''#EXTM3U
#EXTINF:-1,Protected
https://media.example.org/index.m3u8|referer=https://site.example/&user-agent=Mozilla/5.0%20(Windows%20NT%2010.0)&origin=https://site.example
''');
    final headers = playlist.streamFor(playlist.entries.single.id)!.headers;
    expect(headers, {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0)',
      'Referer': 'https://site.example/',
      'Origin': 'https://site.example',
    });
  });

  test('supports repeated pipe delimiters in any order', () {
    final playlist = parser.parse('''#EXTM3U
#EXTINF:-1,Protected
https://media.example.org/index.m3u8|origin=https://site.example|User-Agent=Demo%20Agent|referer=https://site.example/
''');
    final headers = playlist.streamFor(playlist.entries.single.id)!.headers;
    expect(headers['User-Agent'], 'Demo Agent');
    expect(headers['Referer'], 'https://site.example/');
    expect(headers['Origin'], 'https://site.example');
  });

  test('classifies VOD explicitly without treating groups as media types', () {
    final playlist = parser.parse('''#EXTM3U
#EXTINF:-1 group-title="Terror",Movie with an HLS URL
#EXT-X-PLAYLIST-TYPE:VOD
https://media.example.org/film.m3u8
#EXTINF:-1 group-title="Movies",Live movie channel
https://media.example.org/live/channel.ts
#EXTINF:-1 group-title="News",Direct movie
https://media.example.org/movies/film.mp4?token=some-token
''');
    expect(playlist.forKind(LibraryKind.movies, 'a'), hasLength(2));
    expect(playlist.forKind(LibraryKind.live, 'a'), hasLength(1));
    expect(
      playlist.forKind(LibraryKind.live, 'a').single.title,
      'Live movie channel',
    );
    expect(playlist.forKind(LibraryKind.series, 'a'), isEmpty);
    expect(playlist.entries.every((e) => e.sourceScope.isEmpty), isTrue);
    expect(
      playlist.forKind(LibraryKind.movies, 'scope').first.sourceScope,
      'scope',
    );
  });

  test('classifies only explicit VOD or direct MP4, MKV and AVI media', () {
    final playlist = parser.parse('''#EXTM3U
#EXTINF:-1 group-title="Cine" tvg-type="movie",Cinema channel
https://media.example.org/live/cine.m3u8
#EXTINF:-1 group-title="VOD",Movies channel
https://media.example.org/channels/movies.ts
#EXTINF:-1 group-title="General",MP4 file
https://media.example.org/film.MP4?auth=value
#EXTINF:-1 group-title="General",MKV file
https://media.example.org/film.mkv
#EXTINF:-1 group-title="General",AVI file
https://media.example.org/film.avi
#EXTINF:-1,Unmarked HLS movie-like name
https://media.example.org/film.m3u8
''');
    expect(
      playlist.forKind(LibraryKind.live, 'scope').map((entry) => entry.title),
      ['Cinema channel', 'Movies channel', 'Unmarked HLS movie-like name'],
    );
    expect(
      playlist.forKind(LibraryKind.movies, 'scope').map((entry) => entry.title),
      ['MP4 file', 'MKV file', 'AVI file'],
    );
    expect(playlist.forKind(LibraryKind.series, 'scope'), isEmpty);
  });

  test('VOD markers apply only to the entry that follows their EXTINF', () {
    final playlist = parser.parse('''#EXTM3U
#EXT-X-PLAYLIST-TYPE:VOD
#EXTINF:-1,Live before a movie
https://media.example.org/live-before.m3u8
#EXTINF:-1,Film by marker
#EXT-X-PLAYLIST-TYPE:VOD
https://media.example.org/film.m3u8|origin=https://media.example.org
#EXTINF:-1,Live after a movie
https://media.example.org/live-after.m3u8
''');
    expect(playlist.entries.map((entry) => entry.kind), [
      LibraryKind.live,
      LibraryKind.movies,
      LibraryKind.live,
    ]);
    expect(playlist.entries.map((entry) => entry.channelNumber), [1, null, 2]);
    expect(
      playlist.streamFor(playlist.entries[1].id)?.headers['Origin'],
      'https://media.example.org',
    );
  });

  test('dangling VOD markers do not create playable entries', () {
    expect(
      () => parser.parse('''#EXTM3U
#EXTINF:-1,No URL
#EXT-X-PLAYLIST-TYPE:VOD
'''),
      throwsA(isA<Exception>()),
    );
  });

  test('still rejects genuine VOD HLS manifests with media segments', () {
    expect(
      () => parser.parse('''#EXTM3U
#EXT-X-VERSION:3
#EXT-X-PLAYLIST-TYPE:VOD
#EXT-X-TARGETDURATION:8
#EXTINF:7.0,
segment0001.ts
#EXT-X-ENDLIST
'''),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'reclassifying a previous channel does not change its stream identity',
    () {
      const live = '''#EXTM3U
#EXTINF:-1,Movie
https://media.example.org/film.m3u8
''';
      const movie = '''#EXTM3U
#EXTINF:-1,Movie
#EXT-X-PLAYLIST-TYPE:VOD
https://media.example.org/film.m3u8
''';
      final previous = parser.parse(live).entries.single;
      final current = parser.parse(movie).entries.single;
      expect(current.id, previous.id);
      expect(previous.kind, LibraryKind.live);
      expect(current.kind, LibraryKind.movies);
    },
  );

  test('keeps identity stable when list order changes', () {
    const a = '#EXTINF:-1,One\nhttps://media.example.org/one.ts\n';
    const b = '#EXTINF:-1,Two\nhttps://media.example.org/two.ts\n';
    final first = parser.parse('#EXTM3U\n$a$b');
    final second = parser.parse('#EXTM3U\n$b$a');
    expect(first.entries.first.id, second.entries.last.id);
  });

  test('resolves relative media URLs against final playlist URL', () {
    final playlist = parser.parse('''#EXTM3U
#EXTINF:-1,One
../channel/index.m3u8
''', baseUri: Uri.parse('https://example.org/iptv/live/list.m3u'));
    expect(
      playlist.streamFor(playlist.entries.single.id)!.uri.toString(),
      'https://example.org/iptv/channel/index.m3u8',
    );
  });

  test('rejects HLS manifests instead of making segments into channels', () {
    expect(
      () => parser.parse('''#EXTM3U
#EXT-X-TARGETDURATION:10
#EXTINF:9.0,
segment1.ts
'''),
      throwsA(isA<Exception>()),
    );
  });

  test('skips unsupported header names, duplicates, and header injection', () {
    final playlist = parser.parse('''#EXTM3U
#EXTINF:-1,Unknown header
https://media.example.org/one.m3u8|host=evil.example
#EXTINF:-1,Duplicate
https://media.example.org/two.m3u8|origin=https://example.org|origin=https://bad.example
#EXTINF:-1,CRLF
https://media.example.org/three.m3u8|user-agent=hello%0D%0AHost:evil
#EXTINF:-1,Valid
https://media.example.org/four.m3u8
''');
    expect(playlist.entries.single.title, 'Valid');
  });

  test('skips unsafe URL schemes without contacting them', () {
    final playlist = parser.parse('''#EXTM3U
#EXTINF:-1,Local file
file:///etc/passwd
#EXTINF:-1,Regular
https://media.example.org/live.m3u8
''');
    expect(playlist.entries.single.title, 'Regular');
  });
}
