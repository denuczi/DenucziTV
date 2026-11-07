import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/features/personal_library/domain/playback_policy.dart';

void main() {
  test('resume only for meaningful unfinished on-demand positions', () {
    expect(
      PlaybackPolicy.canResume(
        positionMs: 420000,
        durationMs: 1200000,
        completed: false,
      ),
      isTrue,
    );
    expect(
      PlaybackPolicy.canResume(
        positionMs: 5000,
        durationMs: 1200000,
        completed: false,
      ),
      isFalse,
    );
    expect(
      PlaybackPolicy.canResume(
        positionMs: 420000,
        durationMs: 0,
        completed: false,
      ),
      isFalse,
    );
    expect(
      PlaybackPolicy.canResume(
        positionMs: 420000,
        durationMs: 1200000,
        completed: true,
      ),
      isFalse,
    );
    expect(
      PlaybackPolicy.canResume(
        positionMs: 1170000,
        durationMs: 1200000,
        completed: false,
      ),
      isFalse,
    );
  });

  test('completion threshold handles unknown and short durations', () {
    expect(
      PlaybackPolicy.isComplete(positionMs: 95000, durationMs: 100000),
      isTrue,
    );
    expect(
      PlaybackPolicy.isComplete(positionMs: 94999, durationMs: 100000),
      isFalse,
    );
    expect(
      PlaybackPolicy.isComplete(positionMs: 10000, durationMs: 0),
      isFalse,
    );
  });
}
