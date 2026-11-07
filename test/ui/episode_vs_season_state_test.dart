import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/models/app_controller.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/features/downloads/data/download_manager.dart';
import 'package:denuczi_tv/features/downloads/domain/download_task.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/library/presentation/series_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _EpisodeDownloadManager extends DownloadManager {
  _EpisodeDownloadManager(super.network, super.settings);

  @override
  DownloadTask? taskForMedia(String accountId, MediaEntry media) {
    if (media.id == 'ep1') {
      return const DownloadTask(
        id: 'episode-task',
        title: 'Pilot',
        destination: '/virtual/pilot.mp4',
        status: DownloadStatus.downloading,
        bytesReceived: 25,
        totalBytes: 100,
      );
    }
    return null;
  }
}

void main() {
  testWidgets(
    'one downloading episode does not mark the whole season downloading',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final preferences = SharedPreferencesAsync();
      final network = NetworkClient();
      final settings = SettingsStore(preferences);
      final manager = _EpisodeDownloadManager(network, settings);
      final controller = AppController(
        network: network,
        api: XtreamApi(network),
        accounts: AccountStore(preferences, const FlutterSecureStorage()),
        settings: settings,
        downloads: manager,
      );
      controller.showDownloadControls = true;
      addTearDown(controller.dispose);
      const series = MediaEntry(
        id: 'show',
        title: 'Example series',
        kind: LibraryKind.series,
      );
      const episode1 = MediaEntry(
        id: 'ep1',
        title: 'Pilot',
        kind: LibraryKind.series,
        seasonNumber: 1,
        episodeNumber: 1,
      );
      const episode2 = MediaEntry(
        id: 'ep2',
        title: 'Episode Two',
        kind: LibraryKind.series,
        seasonNumber: 1,
        episodeNumber: 2,
      );
      const details = SeriesDetails(
        episodesBySeason: {
          1: [episode1, episode2],
        },
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: controller,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => SeriesDialog(
                        series: series,
                        detailsLoader: () async => details,
                      ),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Download 1 remaining'), findsOneWidget);
      expect(find.text('Downloading season'), findsNothing);
      final seasonAction = tester.widget<TextButton>(
        find.byKey(const Key('downloadSeasonAction')),
      );
      expect(seasonAction.onPressed, isNotNull);
      final compact = find.byKey(const Key('download-action-series-ep1'));
      expect(compact, findsOneWidget);
      expect(tester.widget<OutlinedButton>(compact).onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
