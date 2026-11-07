import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/models/app_controller.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/core/theme/app_theme.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/library/presentation/series_dialog.dart';
import 'package:denuczi_tv/features/library/presentation/media_artwork.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets('closing player returns to the same series episode list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final preferences = SharedPreferencesAsync();
    final network = NetworkClient();
    final controller = AppController(
      network: network,
      api: XtreamApi(network),
      accounts: AccountStore(preferences, const FlutterSecureStorage()),
      settings: SettingsStore(preferences),
    );
    addTearDown(controller.dispose);

    const episode1 = MediaEntry(
      id: 'ep1',
      title: 'Pilot',
      kind: LibraryKind.series,
      seasonNumber: 1,
      episodeNumber: 1,
      imageUrl: 'https://provider.example/pilot.jpg',
    );
    const episode2 = MediaEntry(
      id: 'ep2',
      title: 'Second episode',
      kind: LibraryKind.series,
      seasonNumber: 1,
      episodeNumber: 2,
    );
    const series = MediaEntry(
      id: 'show',
      title: 'Example series',
      kind: LibraryKind.series,
      imageUrl: 'https://provider.example/series.jpg',
    );
    const details = SeriesDetails(
      episodesBySeason: {
        1: [episode1, episode2],
      },
    );
    var launched = false;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => SeriesDialog(
                      series: series,
                      detailsLoader: () async => details,
                      playbackLauncher: (context, queue, index) async {
                        expect(index, 0);
                        expect(queue.length, 2);
                        launched = true;
                        await showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Player is open'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close player'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  child: const Text('Open series'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open series'));
    await tester.pumpAndSettle();
    expect(find.text('Pilot'), findsOneWidget);
    expect(
      tester
          .widget<MediaArtwork>(find.byKey(const Key('episodeArtwork-0')))
          .imageUrl,
      'https://provider.example/pilot.jpg',
    );
    expect(
      tester
          .widget<MediaArtwork>(find.byKey(const Key('episodeArtwork-1')))
          .imageUrl,
      'https://provider.example/series.jpg',
    );
    await tester.tap(find.byKey(const Key('episode-0')));
    await tester.pumpAndSettle();
    expect(launched, isTrue);
    expect(find.text('Player is open'), findsOneWidget);
    await tester.tap(find.text('Close player'));
    await tester.pumpAndSettle();
    expect(find.text('Pilot'), findsOneWidget);
    expect(find.text('Second episode'), findsOneWidget);
    expect(find.text('1 season'), findsOneWidget);
    expect(find.text('2 episodes total'), findsOneWidget);
    expect(find.text('2 episodes in season 1'), findsOneWidget);
    final selectedSeason = find.byKey(const Key('seasonChip-1'));
    expect(selectedSeason, findsOneWidget);
    expect(tester.widget<ChoiceChip>(selectedSeason).selected, isTrue);
    expect(tester.takeException(), isNull);
  });
}
