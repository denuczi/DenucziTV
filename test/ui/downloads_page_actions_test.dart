import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/models/app_controller.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/platform/desktop_file_opener.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/features/downloads/data/download_manager.dart';
import 'package:denuczi_tv/features/downloads/domain/download_task.dart';
import 'package:denuczi_tv/features/downloads/presentation/downloads_page.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _RecordingFileOpener extends DesktopFileOpener {
  String? played;
  String? openedFolderFor;

  @override
  Future<void> play(String path) async {
    played = path;
  }

  @override
  Future<void> openContainingFolder(String path) async {
    openedFolderFor = path;
  }
}

void main() {
  testWidgets('completed download has independent file and history actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 960);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();

    // This widget test verifies presentation and confirmation behavior only.
    // No real file system operations belong in a fake-async widget test;
    // file deletion and persistence are covered by dedicated service tests.
    const destination = '/virtual/downloads/Film.mp4';
    final preferences = SharedPreferencesAsync();
    await preferences.setString(
      'downloads.history.v1',
      jsonEncode([
        DownloadTask(
          id: 'saved',
          title: 'Film',
          destination: destination,
          status: DownloadStatus.completed,
        ).toJson(),
      ]),
    );

    final network = NetworkClient();
    final settings = SettingsStore(preferences);
    final manager = DownloadManager(network, settings);
    await manager.initialize();
    final controller = AppController(
      network: network,
      api: XtreamApi(network),
      accounts: AccountStore(preferences, const FlutterSecureStorage()),
      settings: settings,
      downloads: manager,
    );
    addTearDown(controller.dispose);
    final opener = _RecordingFileOpener();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(body: DownloadsPage(fileOpener: opener)),
        ),
      ),
    );
    await tester.pump();

    final transferTitle = find.text('Transfer activity');
    final clearHistory = find.text('Clear history');
    expect(transferTitle, findsOneWidget);
    expect(clearHistory, findsOneWidget);
    expect(
      tester.getTopLeft(clearHistory).dx,
      greaterThan(tester.getTopRight(transferTitle).dx),
    );

    await tester.tap(clearHistory);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Clear download history?'), findsOneWidget);
    // AlertDialog itself spans the route. Measure its Material surface instead.
    final dialogSurface = find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Material),
        )
        .first;
    expect(tester.getSize(dialogSurface).width, lessThanOrEqualTo(460));
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(manager.tasks.length, 1);

    expect(find.byKey(const Key('play-download-saved')), findsOneWidget);
    expect(find.byKey(const Key('open-folder-saved')), findsOneWidget);
    expect(find.byKey(const Key('remove-history-saved')), findsOneWidget);
    expect(find.byKey(const Key('delete-file-saved')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('play-download-saved')));
    await tester.tap(find.byKey(const Key('play-download-saved')));
    await tester.pump();
    expect(opener.played, destination);

    await tester.tap(find.byKey(const Key('open-folder-saved')));
    await tester.pump();
    expect(opener.openedFolderFor, destination);

    await tester.tap(find.byKey(const Key('delete-file-saved')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Delete downloaded file?'), findsOneWidget);
    expect(find.text('Keep file'), findsOneWidget);
    await tester.tap(find.text('Keep file'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(manager.tasks.single.destination, destination);
    expect(manager.tasks.length, 1);

    await tester.tap(find.byKey(const Key('remove-history-saved')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Remove history entry?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(manager.tasks.length, 1);
    expect(manager.tasks.single.destination, destination);
  });
}
