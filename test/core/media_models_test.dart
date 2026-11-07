import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';

void main() {
  test('parses numeric and string IDs and uses placeholder titles', () {
    final item = MediaEntry.fromJson({
      'stream_id': 42,
      'category_id': '8',
    }, LibraryKind.live);
    expect(item.id, '42');
    expect(item.title, 'Untitled');
    expect(item.categoryId, '8');
  });

  test('ignores malformed episodes while retaining valid seasons', () {
    final series = SeriesDetails.fromJson({
      'episodes': {
        '1': [
          {
            'id': '12',
            'title': 'Pilot',
            'episode_num': 1,
            'container_extension': 'mkv',
          },
          {'title': 'Missing ID'},
        ],
        'invalid': [
          {'id': 3},
        ],
      },
    });
    expect(series.episodesBySeason.keys, [1]);
    expect(series.episodesBySeason[1]!.single.title, 'Pilot');
    expect(series.episodesBySeason[1]!.single.playbackExtension(), 'mkv');
  });
  test('uses provider episode artwork without modifying URLs', () {
    final nested = MediaEntry.episode({
      'id': '7',
      'title': 'Pilot',
      'info': {
        'movie_image': 'https://provider.example/episode-7.jpg',
        'plot': 'Episode description',
      },
    }, 1);
    expect(nested.imageUrl, 'https://provider.example/episode-7.jpg');
    expect(nested.plot, 'Episode description');

    final direct = MediaEntry.episode({
      'id': 8,
      'info': null,
      'cover': 'https://provider.example/episode-8.jpg',
    }, 1);
    expect(direct.imageUrl, 'https://provider.example/episode-8.jpg');

    final missing = MediaEntry.episode({'id': 9, 'info': 'invalid'}, 1);
    expect(missing.imageUrl, isNull);
  });

  test(
    'reports season totals and per-season episode counts from provider data',
    () {
      const first = MediaEntry(
        id: 'a',
        title: 'Pilot',
        kind: LibraryKind.series,
        seasonNumber: 1,
        episodeNumber: 1,
      );
      const second = MediaEntry(
        id: 'b',
        title: 'Second',
        kind: LibraryKind.series,
        seasonNumber: 1,
        episodeNumber: 2,
      );
      const third = MediaEntry(
        id: 'c',
        title: 'Finale',
        kind: LibraryKind.series,
        seasonNumber: 2,
        episodeNumber: 1,
      );
      const details = SeriesDetails(
        episodesBySeason: {
          1: [first, second],
          2: [third],
        },
      );
      expect(details.seasonCount, 2);
      expect(details.episodeCount, 3);
      expect(details.episodeCountForSeason(1), 2);
      expect(details.episodeCountForSeason(2), 1);
      expect(details.episodeCountForSeason(99), 0);
      const missing = SeriesDetails(episodesBySeason: {});
      expect(missing.seasonCount, 0);
      expect(missing.episodeCount, 0);
    },
  );
}
