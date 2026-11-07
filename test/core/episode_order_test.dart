import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';

void main() {
  test('episodes are ordered numerically within a season', () {
    final details = SeriesDetails.fromJson({
      'episodes': {
        '2': [
          {'id': 's2e3', 'title': 'Three', 'episode_num': 3},
          {'id': 's2e1', 'title': 'One', 'episode_num': 1},
          {'id': 's2e2', 'title': 'Two', 'episode_num': 2},
        ],
        '1': [
          {'id': 's1e2', 'title': 'Two', 'episode_num': 2},
          {'id': 's1e1', 'title': 'One', 'episode_num': 1},
        ],
      },
    });
    expect(details.episodesBySeason[1]!.map((e) => e.id), ['s1e1', 's1e2']);
    expect(details.episodesBySeason[2]!.map((e) => e.id), [
      's2e1',
      's2e2',
      's2e3',
    ]);
    expect(details.playbackQueue.map((e) => e.id), [
      's1e1',
      's1e2',
      's2e1',
      's2e2',
      's2e3',
    ]);
  });

  test('episodes with matching or unknown numbers retain source order', () {
    final details = SeriesDetails.fromJson({
      'episodes': {
        '1': [
          {'id': 'first', 'episode_num': 1},
          {'id': 'second', 'episode_num': 1},
          {'id': 'unknown'},
        ],
      },
    });
    expect(details.episodesBySeason[1]!.map((e) => e.id), [
      'first',
      'second',
      'unknown',
    ]);
  });
}
