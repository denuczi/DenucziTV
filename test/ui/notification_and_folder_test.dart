import 'dart:async';
import 'dart:io';

import 'package:denuczi_tv/core/errors/app_exception.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/features/downloads/data/download_manager.dart';
import 'package:denuczi_tv/features/downloads/presentation/download_folder_prompt.dart';
import 'package:denuczi_tv/shared/notifications/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('notifications render over an open modal and can be dismissed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Media details'),
                  content: FilledButton(
                    onPressed: () => AppNotice.show(
                      dialogContext,
                      level: NoticeLevel.info,
                      title: 'Download started',
                      message: 'Queued for transfer.',
                    ),
                    child: const Text('Queue video'),
                  ),
                ),
              ),
              child: const Text('Open details'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Queue video'));
    await tester.pump();
    expect(find.text('Download started'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss notification'));
    await tester.pump();
    expect(find.text('Download started'), findsNothing);
    expect(find.text('Media details'), findsOneWidget);
  });

  test('download directory is validated and persisted', () async {
    final folder = await Directory.systemTemp.createTemp('denuczitv-folder-');
    final network = NetworkClient();
    final settings = SettingsStore(SharedPreferencesAsync());
    final manager = DownloadManager(network, settings);
    try {
      await manager.initialize();
      expect(manager.directory, isNull);

      await expectLater(
        manager.setDirectory('${folder.path}/missing'),
        throwsA(isA<AppException>()),
      );
      expect(manager.directory, isNull);
      expect(await settings.readDownloadDirectory(), isNull);

      await manager.setDirectory(folder.path);
      expect(manager.directory, folder.absolute.path);
      expect(await settings.readDownloadDirectory(), folder.absolute.path);
      expect(manager.tasks, isEmpty);
    } finally {
      manager.dispose();
      network.dispose();
      await folder.delete(recursive: true);
    }
  });

  testWidgets('cancelling folder selection preserves the media dialog', (
    tester,
  ) async {
    final network = NetworkClient();
    final manager = _RecordingDownloadManager(
      network,
      SettingsStore(SharedPreferencesAsync()),
    );
    addTearDown(() {
      manager.dispose();
      network.dispose();
    });
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Media details'),
                  content: FilledButton(
                    onPressed: () async {
                      result = await ensureDownloadFolder(
                        dialogContext,
                        manager,
                      );
                    },
                    child: const Text('Download this video'),
                  ),
                ),
              ),
              child: const Text('Open details'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download this video'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a download folder'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(manager.directory, isNull);
    expect(find.text('Media details'), findsOneWidget);
  });

  testWidgets('native folder picker opens after the Flutter prompt closes', (
    tester,
  ) async {
    final network = NetworkClient();
    final manager = _RecordingDownloadManager(
      network,
      SettingsStore(SharedPreferencesAsync()),
    );
    addTearDown(() {
      manager.dispose();
      network.dispose();
    });
    final selection = Completer<String?>();
    var pickerCalls = 0;
    bool? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (mediaContext) => AlertDialog(
                  title: const Text('Media details'),
                  content: FilledButton(
                    onPressed: () async {
                      result = await ensureDownloadFolder(
                        mediaContext,
                        manager,
                        selectDirectory: (_) {
                          pickerCalls++;
                          expect(
                            find.text('Choose a download folder'),
                            findsNothing,
                          );
                          expect(find.text('Media details'), findsOneWidget);
                          return selection.future;
                        },
                      );
                    },
                    child: const Text('Download this video'),
                  ),
                ),
              ),
              child: const Text('Open details'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download this video'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a download folder'), findsOneWidget);

    await tester.tap(find.text('Choose folder'));
    await tester.pumpAndSettle();
    expect(pickerCalls, 1);
    expect(find.text('Choose a download folder'), findsNothing);
    expect(find.text('Media details'), findsOneWidget);
    expect(result, isNull);

    selection.complete(null);
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(manager.directory, isNull);
  });

  testWidgets('folder selection reaches manager and preserves media details', (
    tester,
  ) async {
    final network = NetworkClient();
    final manager = _RecordingDownloadManager(
      network,
      SettingsStore(SharedPreferencesAsync()),
    );
    addTearDown(() {
      manager.dispose();
      network.dispose();
    });
    bool? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (mediaContext) => AlertDialog(
                  title: const Text('Media details'),
                  content: FilledButton(
                    onPressed: () async {
                      result = await ensureDownloadFolder(
                        mediaContext,
                        manager,
                        selectDirectory: (_) async => '/virtual/downloads',
                      );
                    },
                    child: const Text('Download this video'),
                  ),
                ),
              ),
              child: const Text('Open details'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download this video'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose folder'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(manager.directory, '/virtual/downloads');
    expect(find.text('Choose a download folder'), findsNothing);
    expect(find.text('Media details'), findsOneWidget);
  });

  testWidgets('invalid directory can be retried without losing media dialog', (
    tester,
  ) async {
    final network = NetworkClient();
    final manager = _RecordingDownloadManager(
      network,
      SettingsStore(SharedPreferencesAsync()),
    );
    addTearDown(() {
      manager.dispose();
      network.dispose();
    });
    manager.rejectedPath = '/virtual/missing';
    var pickerCalls = 0;
    bool? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (mediaContext) => AlertDialog(
                  title: const Text('Media details'),
                  content: FilledButton(
                    onPressed: () async {
                      result = await ensureDownloadFolder(
                        mediaContext,
                        manager,
                        selectDirectory: (_) async {
                          pickerCalls++;
                          return pickerCalls == 1
                              ? '/virtual/missing'
                              : '/virtual/downloads';
                        },
                      );
                    },
                    child: const Text('Download this video'),
                  ),
                ),
              ),
              child: const Text('Open details'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download this video'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose folder'));
    await tester.pumpAndSettle();

    expect(pickerCalls, 1);
    expect(manager.directory, isNull);
    expect(find.text('The selected directory does not exist.'), findsOneWidget);
    expect(find.text('Media details'), findsOneWidget);
    await tester.tap(find.text('Choose folder'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(pickerCalls, 2);
    expect(manager.directory, '/virtual/downloads');
  });
}

/// Widget tests use simulated time and must not perform real filesystem I/O.
/// Directory validation and preference persistence are tested separately.
class _RecordingDownloadManager extends DownloadManager {
  _RecordingDownloadManager(super.network, super.settings);

  String? _selectedDirectory;
  String? rejectedPath;

  @override
  String? get directory => _selectedDirectory;

  @override
  Future<void> setDirectory(String selected) async {
    if (selected == rejectedPath) {
      throw const AppException('The selected directory does not exist.');
    }
    _selectedDirectory = selected;
  }
}
