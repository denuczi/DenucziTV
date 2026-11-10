import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:denuczi_tv/features/settings/presentation/settings_page.dart';
import 'package:denuczi_tv/features/downloads/data/download_manager.dart';
import 'package:denuczi_tv/features/updates/presentation/software_update_controls.dart';
import 'package:denuczi_tv/features/updates/application/update_controller.dart';
import 'package:denuczi_tv/features/updates/data/update_preferences.dart';
import 'package:denuczi_tv/features/updates/domain/stable_release.dart';
import 'package:denuczi_tv/features/updates/presentation/startup_update_listener.dart';
import 'package:denuczi_tv/features/updates/presentation/update_dialog.dart';
import 'package:denuczi_tv/l10n/app_localizations.dart';

import '../helpers/protected_account_fixtures.dart';
import 'update_fixtures.dart';

class _BusyDownloads extends DownloadManager {
  _BusyDownloads(super.network, super.settings);
  int active = 1;
  @override
  int get activeCount => active;
}

void main() {
  late SharedPreferencesAsync preferences;
  late UpdatePreferences storage;
  late FakeReleaseApi api;
  late List<Uri> opened;
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    preferences = SharedPreferencesAsync();
    storage = UpdatePreferences(preferences);
    api = FakeReleaseApi();
    opened = [];
  });

  UpdateController create({Future<bool> Function(Uri)? launcher}) {
    final controller = UpdateController(
      api: api,
      preferences: storage,
      installedVersion: () async => '0.6.2+1',
      target: () async => UpdateTarget.debianX64,
      clock: () => DateTime.utc(2099),
      openUrl:
          launcher ??
          (uri) async {
            opened.add(uri);
            return true;
          },
    );
    addTearDown(controller.dispose);
    return controller;
  }

  Widget host(
    UpdateController updates,
    Widget child, {
    String language = 'en',
    bool dark = false,
    UpdateRouteObserver? routes,
    AppController? app,
  }) => MultiProvider(
    providers: [
      ChangeNotifierProvider<UpdateController>.value(value: updates),
      if (app != null) ChangeNotifierProvider<AppController>.value(value: app),
    ],
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
      navigatorObservers: [?routes],
      home: routes == null
          ? Scaffold(body: child)
          : StartupUpdateListener(
              updates: updates,
              routes: routes,
              child: Scaffold(body: child),
            ),
    ),
  );

  Widget standaloneHost(Widget child, {String language = 'en'}) => MaterialApp(
    theme: AppTheme.light,
    locale: Locale(language),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );

  Widget openButton(UpdateController updates, StableRelease release) => Builder(
    builder: (context) => TextButton(
      onPressed: () => showStableUpdateDialog(context, updates, release),
      child: const Text('Open test update'),
    ),
  );

  for (final language in ['en', 'es']) {
    testWidgets(
      'Store-managed update notice does not require a GitHub controller in $language',
      (tester) async {
        await tester.pumpWidget(
          standaloneHost(
            const SoftwareUpdateControls(storeManaged: true),
            language: language,
          ),
        );
        final context = tester.element(find.byType(SoftwareUpdateControls));
        final l10n = AppLocalizations.of(context)!;
        expect(
          find.byKey(const Key('storeManagedUpdateMessage')),
          findsOneWidget,
        );
        expect(find.text(l10n.updatesStoreManagedTitle), findsOneWidget);
        expect(find.text(l10n.updatesStoreManagedHelp), findsOneWidget);
        expect(find.byKey(const Key('checkForUpdates')), findsNothing);
        expect(find.byKey(const Key('softwareUpdateStatus')), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final language in ['en', 'es']) {
    for (final dark in [false, true]) {
      for (final width in [360.0, 1000.0]) {
        testWidgets(
          'stable modal is accessible in $language, dark=$dark, width=$width',
          (tester) async {
            tester.view.physicalSize = Size(width, width < 400 ? 640 : 820);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            api.releases = [
              releaseFixture(
                'v9.0.0',
                notes: '<script>never execute this</script>\nRelease notes',
              ),
            ];
            final updates = create();
            final release = (await updates.checkManually()).release!;
            await tester.pumpWidget(
              host(
                updates,
                openButton(updates, release),
                language: language,
                dark: dark,
              ),
            );
            await tester.tap(find.text('Open test update'));
            await tester.pumpAndSettle();
            final context = tester.element(find.byType(StableUpdateDialog));
            final l10n = AppLocalizations.of(context)!;
            expect(find.text(l10n.updatesTitle), findsOneWidget);
            expect(find.text(l10n.updatesMaybeLater), findsOneWidget);
            expect(find.text('0.6.2+1'), findsOneWidget);
            expect(find.text('9.0.0'), findsOneWidget);
            expect(
              find.textContaining('<script>never execute this</script>'),
              findsOneWidget,
            );
            expect(
              tester
                  .widget<AlertDialog>(find.byType(AlertDialog))
                  .backgroundColor,
              Theme.of(context).colorScheme.surface,
            );
            expect(tester.takeException(), isNull);
            await tester.tap(find.byKey(const Key('postponeUpdate')));
            await tester.pumpAndSettle();
            expect(find.byType(StableUpdateDialog), findsNothing);
            expect(opened, isEmpty);
            expect(
              (await storage.readPostponement())!.version.canonical,
              '9.0.0',
            );
          },
        );
      }
    }
  }

  for (final language in ['en', 'es']) {
    testWidgets(
      'dialog actions remain usable after window resizing in $language',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1000, 820);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final updates = create();
        final release = (await updates.checkManually()).release!;
        await tester.pumpWidget(
          host(updates, openButton(updates, release), language: language),
        );
        await tester.tap(find.text('Open test update'));
        await tester.pumpAndSettle();
        final later = find.byKey(const Key('postponeUpdate'));
        final download = find.byKey(const Key('downloadUpdate'));
        for (final size in [
          const Size(800, 600),
          const Size(360, 640),
          const Size(1000, 820),
        ]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byType(AlertDialog)).width,
            lessThanOrEqualTo(size.width),
          );
          expect(later.hitTestable(), findsOneWidget);
          expect(download.hitTestable(), findsOneWidget);
          final laterRect = tester.getRect(later);
          final downloadRect = tester.getRect(download);
          if (size.width < 420) {
            expect(downloadRect.top, greaterThan(laterRect.bottom));
          } else {
            expect(downloadRect.top, laterRect.top);
          }
          expect(downloadRect.bottom, lessThanOrEqualTo(size.height));
        }
        await tester.tap(later);
        await tester.pumpAndSettle();
        expect(find.byType(StableUpdateDialog), findsNothing);
        expect(opened, isEmpty);
        expect(await storage.readPostponement(), isNotNull);
      },
    );
  }

  for (final action in ['escape', 'close', 'barrier']) {
    testWidgets('$action dismissal postpones without launching a download', (
      tester,
    ) async {
      final updates = create();
      final release = (await updates.checkManually()).release!;
      await tester.pumpWidget(host(updates, openButton(updates, release)));
      await tester.tap(find.text('Open test update'));
      await tester.pumpAndSettle();
      if (action == 'escape') {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      } else if (action == 'close') {
        await tester.tap(find.byTooltip('Close'));
      } else {
        await tester.tapAt(const Offset(5, 5));
      }
      await tester.pumpAndSettle();
      expect(find.byType(StableUpdateDialog), findsNothing);
      expect(opened, isEmpty);
      expect(await storage.readPostponement(), isNotNull);
    });
  }

  testWidgets(
    'download opens only the official asset and leaves the application running',
    (tester) async {
      final updates = create();
      final release = (await updates.checkManually()).release!;
      await tester.pumpWidget(host(updates, openButton(updates, release)));
      await tester.tap(find.text('Open test update'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('downloadUpdate')));
      await tester.pumpAndSettle();
      expect(opened.single.pathSegments.last, 'denuczitv_9.0.0+1-1_amd64.deb');
      expect(find.byType(StableUpdateDialog), findsNothing);
      expect(find.text('Open test update'), findsOneWidget);
      expect(await storage.readPostponement(), isNull);
    },
  );

  testWidgets(
    'browser failure stays in the modal with a localised retryable message',
    (tester) async {
      final updates = create(
        launcher: (_) async => throw StateError('Sensitive exception'),
      );
      final release = (await updates.checkManually()).release!;
      await tester.pumpWidget(
        host(updates, openButton(updates, release), language: 'es'),
      );
      await tester.tap(find.text('Open test update'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('downloadUpdate')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('updateLaunchError')), findsOneWidget);
      expect(find.textContaining('Sensitive exception'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('downloadUpdate')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('postponeUpdate')));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'missing compatible asset offers release details, never a source zip or another platform',
    (tester) async {
      api.releases = [releaseFixture('v9.0.0', debian: false)];
      final updates = create();
      final release = (await updates.checkManually()).release!;
      await tester.pumpWidget(host(updates, openButton(updates, release)));
      await tester.tap(find.text('Open test update'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('downloadUpdate')), findsNothing);
      expect(find.byKey(const Key('viewUpdateNotes')), findsOneWidget);
      await tester.tap(find.byKey(const Key('viewUpdateNotes')));
      await tester.pumpAndSettle();
      expect(opened.single.path, '/denuczi/DenucziTV/releases/tag/v9.0.0');
      expect(find.byType(StableUpdateDialog), findsOneWidget);
      await tester.tap(find.byKey(const Key('postponeUpdate')));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'startup checks once; navigation, theme, language and returning do not reopen the modal',
    (tester) async {
      final updates = create();
      final routes = UpdateRouteObserver();
      Widget child() => Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Another section'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
          child: const Text('Navigate'),
        ),
      );
      await tester.pumpWidget(host(updates, child(), routes: routes));
      await tester.pumpAndSettle();
      expect(api.requests, 1);
      expect(find.byType(StableUpdateDialog), findsOneWidget);
      await tester.tap(find.byKey(const Key('postponeUpdate')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Navigate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        host(updates, child(), routes: routes, language: 'es', dark: true),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StableUpdateDialog), findsNothing);
      expect(api.requests, 1);
    },
  );

  testWidgets(
    'startup never blocks interaction and late completion cannot interrupt a player route',
    (tester) async {
      api.pending = Completer<void>();
      final updates = create();
      final routes = UpdateRouteObserver();
      await tester.pumpWidget(
        host(
          updates,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Test player'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close player'),
                    ),
                  ],
                ),
              ),
              child: const Text('Play'),
            ),
          ),
          routes: routes,
        ),
      );
      await tester.pump();
      expect(find.text('Play'), findsOneWidget);
      expect(api.requests, 1);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      api.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Test player'), findsOneWidget);
      expect(find.byType(StableUpdateDialog), findsNothing);
      await tester.tap(find.text('Close player'));
      await tester.pumpAndSettle();
      expect(find.byType(StableUpdateDialog), findsNothing);
      expect(updates.latestRelease, isNotNull);
    },
  );

  for (final critical in ['authentication', 'download']) {
    testWidgets(
      'automatic completion during $critical is suppressed for the entire session',
      (tester) async {
        final network = NetworkClient();
        final settings = SettingsStore(preferences);
        final downloads = _BusyDownloads(network, settings)
          ..active = critical == 'download' ? 1 : 0;
        final app = AppController(
          network: network,
          api: CatalogTestApi(network),
          accounts: AccountStore.withSecrets(
            preferences,
            MemoryProtectedSecrets(),
          ),
          settings: settings,
          downloads: downloads,
        );
        app.connecting = critical == 'authentication';
        addTearDown(app.dispose);
        final updates = create();
        await tester.pumpWidget(
          host(
            updates,
            const Text('Home'),
            routes: UpdateRouteObserver(),
            app: app,
          ),
        );
        await tester.pumpAndSettle();
        expect(api.requests, 1);
        expect(updates.latestRelease, isNotNull);
        expect(find.byType(StableUpdateDialog), findsNothing);
        downloads.active = 0;
        downloads.notifyListeners();
        app.connecting = false;
        app.notifyListeners();
        await tester.pumpAndSettle();
        expect(find.byType(StableUpdateDialog), findsNothing);
      },
    );
  }

  testWidgets(
    'disposing the startup widget suppresses late state and dialogs',
    (tester) async {
      api.pending = Completer<void>();
      final updates = create();
      await tester.pumpWidget(
        host(updates, const Text('Home'), routes: UpdateRouteObserver()),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      api.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(StableUpdateDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in ['en', 'es']) {
    testWidgets(
      'Settings places updates above credits and manual checks bypass postponement in $language',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final network = NetworkClient();
        final app = AppController(
          network: network,
          api: CatalogTestApi(network),
          accounts: AccountStore.withSecrets(
            preferences,
            MemoryProtectedSecrets(),
          ),
          settings: SettingsStore(preferences),
        );
        addTearDown(app.dispose);
        final updates = create();
        api.pending = Completer<void>();
        await tester.pumpWidget(
          host(updates, const SettingsPage(), app: app, language: language),
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(SettingsPage)),
        )!;
        expect(
          tester.getTopLeft(find.text(l10n.softwareUpdates)).dy,
          lessThan(tester.getTopLeft(find.text(l10n.createdBy)).dy),
        );
        await tester.ensureVisible(find.byKey(const Key('checkForUpdates')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('checkForUpdates')));
        await tester.pump();
        expect(api.requests, 1);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('checkForUpdates')))
              .onPressed,
          isNull,
        );
        api.pending!.complete();
        await tester.pumpAndSettle();
        expect(find.byType(StableUpdateDialog), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.tap(find.byKey(const Key('postponeUpdate')));
        await tester.pumpAndSettle();
        expect(find.byType(StableUpdateDialog), findsNothing);
        expect(await storage.readPostponement(), isNotNull);
        await tester.tap(find.byKey(const Key('checkForUpdates')));
        await tester.pumpAndSettle();
        expect(api.requests, 2);
        expect(find.byType(StableUpdateDialog), findsOneWidget);
        await tester.tap(find.byKey(const Key('postponeUpdate')));
        await tester.pumpAndSettle();
      },
    );
  }
  for (final language in ['en', 'es']) {
    for (final scenario in ['no-stable', 'up-to-date', 'offline']) {
      testWidgets('manual $scenario feedback is accurate in $language', (
        tester,
      ) async {
        if (scenario == 'no-stable') {
          api.releases = [releaseFixture('v99.0.0', prerelease: true)];
        }
        if (scenario == 'up-to-date') api.releases = [releaseFixture('v0.6.2')];
        if (scenario == 'offline') api.failure = UpdateStatus.offline;
        final updates = create();
        await tester.pumpWidget(
          host(updates, const SoftwareUpdateControls(), language: language),
        );
        await tester.tap(find.byKey(const Key('checkForUpdates')));
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(SoftwareUpdateControls)),
        )!;
        final expected = scenario == 'no-stable'
            ? l10n.updatesNoStable
            : scenario == 'up-to-date'
            ? l10n.updatesUpToDate
            : l10n.updatesOffline;
        expect(
          tester
              .widget<Text>(find.byKey(const Key('softwareUpdateStatus')))
              .data,
          expected,
        );
        expect(find.byType(StableUpdateDialog), findsNothing);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('checkForUpdates')))
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.byTooltip(l10n.dismissNotification));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
    'Maybe later during verification cancels without a delayed download',
    (tester) async {
      final updates = create();
      final release = (await updates.checkManually()).release!;
      api.pendingVerification = Completer<void>();
      await tester.pumpWidget(host(updates, openButton(updates, release)));
      await tester.tap(find.text('Open test update'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('downloadUpdate')));
      await tester.pump();
      expect(api.verifications, 1);
      await tester.tap(find.byKey(const Key('postponeUpdate')));
      await tester.pumpAndSettle();
      expect(api.verificationCancellation!.isCancelled, isTrue);
      api.pendingVerification!.complete();
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(await storage.readPostponement(), isNotNull);
    },
  );
  for (final restoredBeforeResult in [false, true]) {
    testWidgets(
      'startup restoration safety, finished before result=$restoredBeforeResult',
      (tester) async {
        final network = NetworkClient();
        final app = AppController(
          network: network,
          api: CatalogTestApi(network),
          accounts: AccountStore.withSecrets(
            preferences,
            MemoryProtectedSecrets(),
          ),
          settings: SettingsStore(preferences),
        );
        app.connecting = true;
        app.restoringAccount = true;
        addTearDown(app.dispose);
        api.pending = Completer<void>();
        final updates = create();
        await tester.pumpWidget(
          host(
            updates,
            const Text('Home'),
            routes: UpdateRouteObserver(),
            app: app,
          ),
        );
        await tester.pump();
        expect(api.requests, 1);
        if (restoredBeforeResult) {
          app.connecting = false;
          app.restoringAccount = false;
          app.notifyListeners();
        }
        api.pending!.complete();
        await tester.pumpAndSettle();
        expect(
          find.byType(StableUpdateDialog),
          restoredBeforeResult ? findsOneWidget : findsNothing,
        );
        if (restoredBeforeResult) {
          await tester.tap(find.byKey(const Key('postponeUpdate')));
          await tester.pumpAndSettle();
        } else {
          app.connecting = false;
          app.restoringAccount = false;
          app.notifyListeners();
          await tester.pumpAndSettle();
          expect(find.byType(StableUpdateDialog), findsNothing);
        }
      },
    );
  }
}
