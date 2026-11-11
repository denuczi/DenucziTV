import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/player/domain/live_channel_directory.dart';
import 'package:flutter_test/flutter_test.dart';

MediaEntry _live(int number, {String? id}) => MediaEntry(
  id: id ?? '$number',
  title: 'Channel $number',
  kind: LibraryKind.live,
  channelNumber: number,
);

void main() {
  test('numbers remain stable regardless of input order and gaps', () {
    final channels = LiveChannelDirectory([
      _live(12),
      _live(2),
      const MediaEntry(id: 'movie', title: 'Movie', kind: LibraryKind.movies),
      _live(20),
      _live(2, id: 'duplicate-number'),
      _live(21, id: '12'),
    ]);
    expect(channels.length, 3);
    expect(channels.byNumber(12)?.id, '12');
    expect(channels.byNumber(13), isNull);
    expect(channels.stepFrom('2', 1)?.id, '12');
    expect(channels.stepFrom('12', 1)?.id, '20');
    expect(channels.stepFrom('20', 1)?.id, '2');
    expect(channels.stepFrom('2', -1)?.id, '20');
    expect(channels.stepFrom('missing', 1), isNull);
  });

  test('empty directory and absent numbers are handled safely', () {
    final empty = LiveChannelDirectory(const []);
    expect(empty.stepFrom('1', 1), isNull);
    expect(empty.byNumber(1), isNull);
    final invalid = LiveChannelDirectory([
      const MediaEntry(id: '1', title: 'Unknown', kind: LibraryKind.live),
      _live(0),
    ]);
    expect(invalid.isEmpty, isTrue);
  });

  test('large directional step wraps without repeated list scanning', () {
    final directory = LiveChannelDirectory([_live(1), _live(2), _live(3)]);
    expect(directory.stepFrom('1', -4)?.id, '3');
    expect(directory.stepFrom('3', 100)?.id, '1');
  });
}
