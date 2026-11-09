import 'package:denuczi_tv/core/theme/app_theme.dart';
import 'package:denuczi_tv/features/player/presentation/player_video_overlay.dart';
import 'package:denuczi_tv/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class _TestPlatformPlayer extends PlatformPlayer {
  _TestPlatformPlayer() : super(configuration: const PlayerConfiguration());
}

/// Exercises media_kit's real fullscreen routing without a native decoder.
class _TestVideoController implements VideoController {
  _TestVideoController(this.player);

  @override
  final Player player;

  @override
  final notifier = ValueNotifier<PlatformVideoController?>(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final locale in ['en', 'es']) {
    testWidgets('playback errors stay visible in fullscreen ($locale)', (
      tester,
    ) async {
      final player = Player(platformPlayer: _TestPlatformPlayer());
      final controller = _TestVideoController(player);
      final status = ValueNotifier(const PlayerVideoStatus());
      final videoKey = GlobalKey<VideoState>();
      var retries = 0;
      var entered = 0;
      var exited = 0;
      String? failure;
      String? retry;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 640,
                height: 360,
                child: Video(
                  key: videoKey,
                  controller: controller,
                  wakelock: false,
                  subtitleViewConfiguration: const SubtitleViewConfiguration(
                    visible: false,
                  ),
                  onEnterFullscreen: () async => entered++,
                  onExitFullscreen: () async => exited++,
                  controls: (video) => Builder(
                    builder: (context) {
                      final l10n = AppLocalizations.of(context)!;
                      failure = l10n.mediaEnginePlaybackFailed;
                      retry = l10n.retry;
                      return PlayerVideoOverlay(
                        status: status,
                        controls: Align(
                          alignment: Alignment.bottomCenter,
                          child: TextButton(
                            onPressed: video.toggleFullscreen,
                            child: const Text('Toggle fullscreen'),
                          ),
                        ),
                        onRetry: () {
                          retries++;
                          status.value = const PlayerVideoStatus();
                        },
                        onClose: () {},
                        onExploreCatalog: () {},
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Toggle fullscreen'));
      await tester.pumpAndSettle();
      expect(entered, 1);
      expect(find.byType(Video), findsOneWidget);
      expect(find.byType(Video, skipOffstage: false), findsNWidgets(2));

      // The dialog does not rebuild: the shared status must update this route.
      status.value = PlayerVideoStatus(failure: failure);
      await tester.pumpAndSettle();
      expect(find.text(failure!), findsOneWidget);
      expect(find.text(retry!), findsOneWidget);
      expect(entered, 1);
      expect(exited, 0);
      final banner = tester.getRect(find.text(failure!));
      expect(banner.top, greaterThanOrEqualTo(0));
      expect(banner.bottom, lessThanOrEqualTo(tester.view.physicalSize.height));

      await tester.tap(find.text(retry!));
      await tester.pumpAndSettle();
      expect(retries, 1);
      expect(find.text(failure!), findsNothing);
      expect(exited, 0);

      status.value = PlayerVideoStatus(failure: failure);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Toggle fullscreen'));
      await tester.pumpAndSettle();
      expect(exited, 1);
      expect(find.text(failure!), findsOneWidget);
      expect(videoKey.currentState!.isFullscreen(), isFalse);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      status.dispose();
      controller.notifier.dispose();
      await player.dispose();
    });
  }

  testWidgets(
    'blocked playback hides transport controls and exposes exit actions',
    (tester) async {
      final status = ValueNotifier(
        const PlayerVideoStatus(
          failure: 'Source unavailable',
          accessBlocked: true,
          sourceUnavailable: true,
        ),
      );
      addTearDown(status.dispose);
      var closed = false;
      var explored = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlayerVideoOverlay(
              status: status,
              controls: const Text('Transport controls'),
              onRetry: () => fail('Blocked playback must not be retried'),
              onClose: () => closed = true,
              onExploreCatalog: () => explored = true,
            ),
          ),
        ),
      );
      expect(find.text('Transport controls'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Source unavailable'), findsOneWidget);
      await tester.tap(find.text('Explore updated catalog'));
      await tester.tap(find.text('Close player'));
      expect(explored, isTrue);
      expect(closed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
