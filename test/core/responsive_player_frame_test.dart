import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/features/player/presentation/responsive_player_frame.dart';

void main() {
  for (final size in <Size>[
    const Size(1280, 720),
    const Size(1366, 768),
    const Size(900, 540),
  ]) {
    testWidgets('player frame does not overflow at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const ResponsivePlayerFrame(
                      header: Center(child: Text('Player')),
                      video: ColoredBox(color: Colors.black),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Player'), findsOneWidget);
    });
  }
}
