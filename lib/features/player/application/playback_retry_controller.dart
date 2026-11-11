import 'dart:async';

/// Limits automatic reconnects so a failing provider cannot trigger unbounded
/// requests. The player owns this controller and disposes it with the dialog.
class PlaybackRetryController {
  PlaybackRetryController({
    required this.onCountdownChanged,
    required this.onRetry,
    this.maxAutomaticRetries = 3,
    this.retryDelaySeconds = 3,
    this.stablePlaybackPeriod = const Duration(seconds: 10),
  }) : assert(maxAutomaticRetries > 0),
       assert(retryDelaySeconds > 0);

  final void Function(int? seconds) onCountdownChanged;
  final void Function() onRetry;
  final int maxAutomaticRetries;
  final int retryDelaySeconds;
  final Duration stablePlaybackPeriod;

  Timer? _countdown;
  Timer? _stablePlayback;
  int? _secondsRemaining;
  int _automaticRetries = 0;
  bool _disposed = false;

  int? get secondsRemaining => _secondsRemaining;
  int get automaticRetries => _automaticRetries;

  void reportFailure() {
    if (_disposed) return;
    playbackInterrupted();
    if (_countdown != null || _automaticRetries >= maxAutomaticRetries) {
      return;
    }

    _automaticRetries++;
    _secondsRemaining = retryDelaySeconds;
    onCountdownChanged(_secondsRemaining);
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining! > 1) {
        _secondsRemaining = _secondsRemaining! - 1;
        onCountdownChanged(_secondsRemaining);
        return;
      }
      _countdown = null;
      _secondsRemaining = null;
      timer.cancel();
      onCountdownChanged(null);
      onRetry();
    });
  }

  /// A brief start followed by another failure is not stable playback.
  /// Only reset the retry budget once playback has remained healthy.
  void playbackRecovered() {
    if (_disposed) return;
    _clearCountdown();
    _stablePlayback?.cancel();
    _stablePlayback = Timer(stablePlaybackPeriod, () {
      _stablePlayback = null;
      _automaticRetries = 0;
    });
  }

  void playbackInterrupted() {
    _stablePlayback?.cancel();
    _stablePlayback = null;
  }

  /// Manual retries and explicit media/format changes start a new retry budget.
  void reset() {
    if (_disposed) return;
    playbackInterrupted();
    _clearCountdown();
    _automaticRetries = 0;
  }

  void cancelPending() {
    if (_disposed) return;
    playbackInterrupted();
    _clearCountdown();
  }

  void _clearCountdown({bool notify = true}) {
    _countdown?.cancel();
    _countdown = null;
    if (_secondsRemaining != null) {
      _secondsRemaining = null;
      if (notify) onCountdownChanged(null);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clearCountdown(notify: false);
    playbackInterrupted();
  }
}
