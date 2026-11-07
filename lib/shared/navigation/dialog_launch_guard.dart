/// Prevents a second navigation request while an earlier one is pending.
///
/// Acquire before awaiting any provider request, so rapid taps are serialized.
/// Unlike a debounce, this remains engaged until the dialog closes or fails.
class DialogLaunchGuard {
  bool _busy = false;
  bool get isBusy => _busy;

  Future<void> run(Future<void> Function() launch) async {
    if (_busy) {
      return;
    }
    _busy = true;
    try {
      await launch();
    } finally {
      _busy = false;
    }
  }
}
