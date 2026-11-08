import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:denuczi_tv/core/models/app_controller.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/core/theme/app_theme.dart';
import 'package:denuczi_tv/features/downloads/data/download_manager.dart';
import 'package:denuczi_tv/features/downloads/data/download_storage_inspector.dart';
import 'package:denuczi_tv/features/downloads/domain/download_task.dart';
import 'package:denuczi_tv/features/downloads/presentation/downloads_page.dart';
import 'package:denuczi_tv/l10n/app_localizations.dart';
import 'package:denuczi_tv/shared/notifications/app_notice.dart';

import '../helpers/protected_account_fixtures.dart';

class _SnapshotDownloads extends DownloadManager {
  _SnapshotDownloads(super.network, super.settings);

  @override
  List<DownloadTask> get tasks => const [
    DownloadTask(
      id: 'reconnecting',
      title: 'Reconnecting movie',
      destination: '/virtual/movie.mp4',
      status: DownloadStatus.downloading,
      bytesReceived: 500,
      totalBytes: 1000,
      message: 'Reconnecting to resume saved bytes...',
    ),
    DownloadTask(
      id: 'failed',
      title: 'Interrupted movie',
      destination: '/virtual/interrupted.mp4',
      status: DownloadStatus.failed,
      bytesReceived: 500,
      message: 'The server interrupted the connection.',
    ),
  ];
}

class _NoDiskInspector extends DownloadStorageInspector {
  const _NoDiskInspector();

  @override
  Future<DownloadStorageSummary> inspect(List<DownloadTask> tasks) async =>
      const DownloadStorageSummary(
        completedFiles: 0,
        completedBytes: 0,
        partialFiles: 0,
        partialBytes: 0,
        unavailableFiles: 0,
      );
}

void main() {
  for (final language in ['en', 'es']) {
    for (final dark in [false, true]) {
      testWidgets(
        'download recovery and failure use localised messages and distinct colours in $language, dark=$dark',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 1800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          SharedPreferencesAsyncPlatform.instance =
              InMemorySharedPreferencesAsync.empty();
          final preferences = SharedPreferencesAsync();
          final network = NetworkClient();
          final settings = SettingsStore(preferences);
          final app = AppController(
            network: network,
            api: CatalogTestApi(network),
            accounts: AccountStore.withSecrets(
              preferences,
              MemoryProtectedSecrets(),
            ),
            settings: settings,
            downloads: _SnapshotDownloads(network, settings),
          );
          await tester.pumpWidget(
            ChangeNotifierProvider<AppController>(
              create: (_) => app,
              child: MaterialApp(
                theme: dark ? AppTheme.dark : AppTheme.light,
                locale: Locale(language),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: const Scaffold(
                  body: DownloadsPage(storageInspector: _NoDiskInspector()),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final context = tester.element(find.byType(DownloadsPage));
          final l10n = AppLocalizations.of(context)!;
          expect(find.text(l10n.downloadReconnecting), findsOneWidget);
          expect(find.text(l10n.downloadServerInterrupted), findsOneWidget);
          expect(
            find.text('Reconnecting to resume saved bytes...'),
            findsNothing,
          );
          expect(
            find.text('The server interrupted the connection.'),
            findsNothing,
          );
          if (language == 'es') {
            expect(find.text('FAILED'), findsNothing);
            expect(find.text('FALLIDA'), findsOneWidget);
            expect(
              find.textContaining('Puedes volver a intentarlo'),
              findsOneWidget,
            );
          }
          final running = tester.widget<Text>(
            find.text(l10n.downloadStatusDownloading.toUpperCase()),
          );
          final failed = tester.widget<Text>(
            find.text(l10n.downloadStatusFailed.toUpperCase()),
          );
          expect(
            running.style!.color,
            AppPalette.information(Theme.of(context).brightness),
          );
          expect(failed.style!.color, Theme.of(context).colorScheme.error);
          expect(running.style!.color, isNot(failed.style!.color));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final dark in [false, true]) {
    testWidgets(
      'informational download notices do not use the red brand colour, dark=$dark',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => AppNotice.show(
                    context,
                    level: NoticeLevel.info,
                    title: 'Download started',
                  ),
                  child: const Text('Start'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Start'));
        await tester.pump();
        final icon = tester.widget<Icon>(
          find.byIcon(Icons.info_outline_rounded),
        );
        expect(
          icon.color,
          AppPalette.information(dark ? Brightness.dark : Brightness.light),
        );
        final context = tester.element(find.text('Start'));
        expect(icon.color, isNot(Theme.of(context).colorScheme.primary));
        expect(icon.color, isNot(Theme.of(context).colorScheme.error));
        await tester.tap(find.byTooltip('Dismiss notification'));
        await tester.pump();
      },
    );
  }
}
