import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/models/app_controller.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/features/downloads/data/download_manager.dart';
import 'package:denuczi_tv/features/downloads/domain/download_task.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/library/presentation/download_action_button.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _StubDownloadManager extends DownloadManager {
  _StubDownloadManager(super.network, super.settings);
  DownloadTask? current;

  @override
  DownloadTask? taskForMedia(String accountId, MediaEntry entry) => current;

  void change(DownloadTask? next) {
    current = next;
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'download control follows queued, progress and completed states',
    (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final preferences = SharedPreferencesAsync();
      final network = NetworkClient();
      final manager = _StubDownloadManager(network, SettingsStore(preferences));
      final app = AppController(
        network: network,
        api: XtreamApi(network),
        accounts: AccountStore(preferences, const FlutterSecureStorage()),
        settings: SettingsStore(preferences),
        downloads: manager,
      );
      addTearDown(app.dispose);
      const media = MediaEntry(
        id: 'movie-7',
        title: 'Movie',
        kind: LibraryKind.movies,
        containerExtension: 'mp4',
      );
      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: app,
          child: const MaterialApp(
            home: Scaffold(body: DownloadActionButton(media: media)),
          ),
        ),
      );

      final button = find.byType(OutlinedButton);
      expect(find.text('Download'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
      manager.change(
        const DownloadTask(
          id: 'job',
          title: 'Movie',
          destination: '/tmp/movie.mp4',
          status: DownloadStatus.queued,
        ),
      );
      await tester.pump();
      expect(find.text('Queued'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .value,
        isNull,
      );

      manager.change(
        const DownloadTask(
          id: 'job',
          title: 'Movie',
          destination: '/tmp/movie.mp4',
          status: DownloadStatus.downloading,
          bytesReceived: 25,
          totalBytes: 100,
        ),
      );
      await tester.pump();
      expect(find.text('Downloading'), findsOneWidget);
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .value,
        0.25,
      );

      manager.change(
        const DownloadTask(
          id: 'job',
          title: 'Movie',
          destination: '/tmp/movie.mp4',
          status: DownloadStatus.completed,
          bytesReceived: 100,
          totalBytes: 100,
        ),
      );
      await tester.pump();
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    },
  );
}
