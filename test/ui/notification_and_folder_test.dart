import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/features/downloads/data/download_manager.dart';
import 'package:denuczi_tv/features/downloads/presentation/download_folder_prompt.dart';
import 'package:denuczi_tv/shared/notifications/app_notice.dart';
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

  testWidgets('cancelling folder selection preserves the media dialog', (
    tester,
  ) async {
    final network = NetworkClient();
    final manager = DownloadManager(
      network,
      SettingsStore(SharedPreferencesAsync()),
    );
    addTearDown(() {
      manager.dispose();
      network.dispose();
    });
    await manager.initialize();
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
}
