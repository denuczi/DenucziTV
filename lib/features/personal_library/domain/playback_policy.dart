/// Conservative playback progress rules for finite on-demand media.
abstract final class PlaybackPolicy {
  static const int resumeMinimumMs = 30000;
  static const double completionThreshold = 0.95;

  static bool canResume({
    required int positionMs,
    required int durationMs,
    required bool completed,
  }) {
    return !completed &&
        durationMs > 0 &&
        positionMs >= resumeMinimumMs &&
        positionMs < durationMs * completionThreshold;
  }

  static bool isComplete({required int positionMs, required int durationMs}) =>
      durationMs > 0 && positionMs >= durationMs * completionThreshold;
}
