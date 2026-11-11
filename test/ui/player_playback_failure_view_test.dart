import 'package:denuczi_tv/features/player/presentation/player_video_overlay.dart';
import 'package:denuczi_tv/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final locale in ['en', 'es']) {
    testWidgets('failure is centered and contained in the player ($locale)', (
      tester,
    ) async {
      final status = ValueNotifier(
        const PlayerVideoStatus(
          failure: 'Stream unavailable',
          retryCountdownSeconds: 3,
          opening: true,
        ),
      );
      addTearDown(status.dispose);
      var retries = 0;

      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                key: const Key('videoFrame'),
                width: 640,
                height: 360,
                child: PlayerVideoOverlay(
                  status: status,
                  controls: const Text('Native controls'),
                  onRetry: () => retries++,
                  onClose: () {},
                  onExploreCatalog: () {},
                ),
              ),
            ),
          ),
        ),
      );
      final frame = tester.getRect(find.byKey(const Key('videoFrame')));
      final content = tester.getRect(
        find.byKey(const Key('playerFailureContent')),
      );
      expect(content.width, lessThanOrEqualTo(420));
      expect((frame.center.dy - content.center.dy).abs(), lessThan(30));
      expect(find.text('Native controls'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Stream unavailable'), findsOneWidget);
      expect(
        find.text(
          locale == 'es'
              ? 'Reproducción no disponible'
              : 'Playback unavailable',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text(locale == 'es' ? 'Reintentar' : 'Retry'));
      expect(retries, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('small player remains scrollable without overflow', (
    tester,
  ) async {
    final status = ValueNotifier(
      const PlayerVideoStatus(
        failure:
            'This provider returned a longer explanation that should be '
            'readable even when the player is inside a small window.',
        retryCountdownSeconds: 2,
      ),
    );
    addTearDown(status.dispose);
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 180,
              child: PlayerVideoOverlay(
                status: status,
                controls: const SizedBox.shrink(),
                onRetry: () {},
                onClose: () => closed = true,
                onExploreCatalog: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Close player'));
    await tester.tap(find.text('Close player'));
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });
}
