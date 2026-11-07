import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/models/app_controller.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/features/downloads/data/download_manager.dart';
import 'package:denuczi_tv/features/downloads/data/download_storage_inspector.dart';
import 'package:denuczi_tv/features/downloads/domain/download_task.dart';
import 'package:denuczi_tv/features/downloads/presentation/downloads_page.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Avoids real file-system reads in a widget test's fake async environment.
/// Disk accounting is verified in the dedicated storage inspector tests.
class _InMemoryStorageInspector extends DownloadStorageInspector {
  const _InMemoryStorageInspector();

  @override
  Future<DownloadStorageSummary> inspect(List<DownloadTask> tasks) async {
    return const DownloadStorageSummary(
      completedFiles: 0,
      completedBytes: 0,
      partialFiles: 0,
      partialBytes: 0,
      unavailableFiles: 0,
    );
  }
}

void main() {
  testWidgets('history actions align right even when Delete file is absent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final preferences = SharedPreferencesAsync();
    await preferences.setString(
      'downloads.history.v1',
      jsonEncode([
        const DownloadTask(
          id: 'cancelled',
          title: 'Cancelled episode',
          destination: '/missing/episode.mp4',
          status: DownloadStatus.cancelled,
        ).toJson(),
      ]),
    );
    final network = NetworkClient();
    final settings = SettingsStore(preferences);
    final downloads = DownloadManager(network, settings);
    // initialize() examines saved .part files on disk. Run this setup with
    // real asynchronous I/O rather than the widget tester's simulated clock.
    await tester.runAsync(downloads.initialize);
    expect(tester.takeException(), isNull);
    final controller = AppController(
      network: network,
      api: XtreamApi(network),
      accounts: AccountStore(preferences, const FlutterSecureStorage()),
      settings: settings,
      downloads: downloads,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: const MaterialApp(
          home: Scaffold(
            body: DownloadsPage(storageInspector: _InMemoryStorageInspector()),
          ),
        ),
      ),
    );
    await tester.pump();
    final history = find.byKey(const Key('remove-history-cancelled'));
    expect(history, findsOneWidget);
    expect(find.byKey(const Key('delete-file-cancelled')), findsNothing);
    final buttons = find.byKey(const Key('historyActions-cancelled'));
    expect(
      (tester.getRect(buttons).right - tester.getRect(history).right).abs(),
      lessThan(1),
    );
    final folder = find.byKey(const Key('open-folder-cancelled'));
    expect(
      tester.getRect(history).left,
      greaterThan(tester.getRect(folder).right),
    );
    expect(tester.takeException(), isNull);
  });
}
