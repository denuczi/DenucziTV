import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/features/player/presentation/playback_track_menu.dart';

void main() {
  test('identifies a native track without inventing languages', () {
    expect(
      PlaybackTrackMenu.trackLabel('3', 'Surround', 'es'),
      'es · Surround',
    );
    expect(PlaybackTrackMenu.trackLabel('3', null, 'en'), 'en');
    expect(PlaybackTrackMenu.trackLabel('3', null, null), 'Track 3');
  });
}
