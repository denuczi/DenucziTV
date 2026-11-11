import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/features/player/presentation/live_channel_indicator.dart';
import 'package:denuczi_tv/features/player/presentation/player_video_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'video overlay receives channel keys without removing video controls',
    (tester) async {
      final status = ValueNotifier(const PlayerVideoStatus());
      final feedback = ValueNotifier<LiveChannelNotice?>(null);
      final network = NetworkClient();
      addTearDown(status.dispose);
      addTearDown(feedback.dispose);
      addTearDown(network.dispose);
      var downPresses = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: PlayerVideoOverlay(
                status: status,
                controls: const Center(child: Text('Video controls')),
                onRetry: () {},
                onClose: () {},
                onExploreCatalog: () {},
                liveChannelNotice: feedback,
                network: network,
                onChannelKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.arrowDown) {
                    downPresses++;
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Video controls'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      expect(downPresses, 1);
      feedback.value = const LiveChannelNotice.forDigits('205');
      await tester.pumpAndSettle();
      expect(find.text('205'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('channel feedback is hidden for a regular player', (
    tester,
  ) async {
    final status = ValueNotifier(const PlayerVideoStatus());
    final feedback = ValueNotifier<LiveChannelNotice?>(
      const LiveChannelNotice.forDigits('17'),
    );
    final network = NetworkClient();
    addTearDown(status.dispose);
    addTearDown(feedback.dispose);
    addTearDown(network.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerVideoOverlay(
            status: status,
            controls: const Text('Video controls'),
            onRetry: () {},
            onClose: () {},
            onExploreCatalog: () {},
          ),
        ),
      ),
    );
    expect(find.text('17'), findsNothing);
    expect(find.text('Video controls'), findsOneWidget);
  });
}
