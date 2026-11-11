import 'package:denuczi_tv/features/player/application/playback_retry_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('retries after a 3, 2, 1 countdown without duplicate timers', (
    tester,
  ) async {
    final countdowns = <int?>[];
    var retries = 0;
    final controller = PlaybackRetryController(
      onCountdownChanged: countdowns.add,
      onRetry: () => retries++,
    );
    addTearDown(controller.dispose);

    controller.reportFailure();
    controller.reportFailure();
    expect(countdowns, [3]);
    expect(controller.automaticRetries, 1);

    await tester.pump(const Duration(seconds: 1));
    expect(countdowns, [3, 2]);
    await tester.pump(const Duration(seconds: 1));
    expect(countdowns, [3, 2, 1]);
    await tester.pump(const Duration(seconds: 1));
    expect(countdowns, [3, 2, 1, null]);
    expect(retries, 1);
    expect(controller.secondsRemaining, isNull);
  });

  testWidgets('limits automatic retries but allows a new manual attempt', (
    tester,
  ) async {
    var retries = 0;
    final controller = PlaybackRetryController(
      onCountdownChanged: (_) {},
      onRetry: () => retries++,
    );
    addTearDown(controller.dispose);

    for (var attempt = 0; attempt < 3; attempt++) {
      controller.reportFailure();
      await tester.pump(const Duration(seconds: 3));
    }
    expect(retries, 3);
    controller.reportFailure();
    await tester.pump(const Duration(seconds: 5));
    expect(retries, 3);

    controller.reset();
    controller.reportFailure();
    await tester.pump(const Duration(seconds: 3));
    expect(retries, 4);
  });

  testWidgets('recovery cancels retry and only resets budget after stability', (
    tester,
  ) async {
    var retries = 0;
    final controller = PlaybackRetryController(
      onCountdownChanged: (_) {},
      onRetry: () => retries++,
    );
    addTearDown(controller.dispose);

    controller.reportFailure();
    expect(controller.automaticRetries, 1);
    controller.playbackRecovered();
    await tester.pump(const Duration(seconds: 3));
    expect(retries, 0);
    controller.playbackInterrupted();
    controller.reportFailure();
    expect(controller.automaticRetries, 2);

    controller.playbackRecovered();
    await tester.pump(const Duration(seconds: 10));
    expect(controller.automaticRetries, 0);
    controller.reportFailure();
    expect(controller.automaticRetries, 1);
    expect(controller.secondsRemaining, 3);

    // testWidgets checks for pending timers before addTearDown callbacks run.
    // Dispose within the test body so the last countdown cannot outlive it.
    controller.dispose();
  });

  testWidgets('cancel and dispose prevent late callbacks', (tester) async {
    final countdowns = <int?>[];
    var retries = 0;
    final controller = PlaybackRetryController(
      onCountdownChanged: countdowns.add,
      onRetry: () => retries++,
    );
    controller.reportFailure();
    controller.cancelPending();
    expect(countdowns, [3, null]);
    controller.reportFailure();
    controller.dispose();
    await tester.pump(const Duration(seconds: 10));
    expect(retries, 0);
    expect(countdowns, [3, null, 3]);
  });
}
