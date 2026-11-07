import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';

void main() {
  test('parses optional VOD metadata without fabricating absent fields', () {
    final details = MediaDetails.fromJson({
      'info': {
        'plot': 'Story summary',
        'genre': 'Science Fiction',
        'releasedate': '2025-01-02',
        'duration': '112 min',
        'cast': 'Actor A, Actor B',
      },
    });
    expect(details.plot, 'Story summary');
    expect(details.genre, 'Science Fiction');
    expect(details.releaseDate, '2025-01-02');
    expect(details.rating, isNull);
  });

  test('retains series information and parsed episodes', () {
    final details = SeriesDetails.fromJson({
      'info': {'plot': 'A long-running show', 'genre': 'Drama'},
      'episodes': {
        '1': [
          {'id': '42', 'title': 'Episode 1', 'episode_num': 1},
        ],
      },
    });
    expect(details.metadata.plot, 'A long-running show');
    expect(details.metadata.genre, 'Drama');
    expect(details.episodesBySeason[1]?.single.title, 'Episode 1');
  });
}
