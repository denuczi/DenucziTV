import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/models/app_controller.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/core/theme/app_theme.dart';
import 'package:denuczi_tv/features/connection/presentation/account_details_dialog.dart';
import 'package:denuczi_tv/features/connection/presentation/connect_dialog.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/library/presentation/media_actions.dart';
import 'package:denuczi_tv/l10n/app_localizations.dart';
import 'package:denuczi_tv/features/settings/presentation/settings_page.dart';

import '../helpers/protected_account_fixtures.dart';

void main() {
  late AppController app;
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final preferences = SharedPreferencesAsync();
    final network = NetworkClient();
    app = AppController(
      network: network,
      api: CatalogTestApi(network),
      accounts: AccountStore.withSecrets(preferences, MemoryProtectedSecrets()),
      settings: SettingsStore(preferences),
    );
  });
  tearDown(() => app.dispose());

  Widget host(Widget child, {String language = 'en', bool dark = false}) =>
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          locale: Locale(language),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      );

  for (final language in ['en', 'es']) {
    testWidgets(
      'protected form requires a name and hides manual fields in $language',
      (tester) async {
        await tester.pumpWidget(
          host(const ConnectDialog(), language: language),
        );
        final selector = tester
            .widget<DropdownButtonFormField<AccountConnectionType>>(
              find.byType(DropdownButtonFormField<AccountConnectionType>),
            );
        selector.onChanged!(AccountConnectionType.protectedSingleLink);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('username')), findsNothing);
        expect(find.byKey(const Key('password')), findsNothing);
        await tester.tap(
          find.byWidgetPredicate((widget) => widget is FilledButton),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            language == 'es'
                ? 'Introduce un nombre para la cuenta.'
                : 'Enter an account name.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    for (final dark in [false, true]) {
      testWidgets(
        'protected details expose no connection data in $language, dark=$dark',
        (tester) async {
          const account = Account(
            id: 'protected',
            label: 'My protected account',
            serverUrl: 'https://private-provider.example',
            username: 'private-user',
            connectionType: AccountConnectionType.protectedSingleLink,
          );
          app.activeAccount = account;
          app.accountStatus = const AccountStatus(
            authorized: true,
            status: 'private-user',
          );
          await tester.pumpWidget(
            host(const AccountDetailsDialog(), language: language, dark: dark),
          );
          await tester.pumpAndSettle();
          expect(find.text('My protected account'), findsOneWidget);
          expect(
            find.text(
              language == 'es'
                  ? 'Vencimiento no informado'
                  : 'Expiration not provided',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('private-provider'), findsNothing);
          expect(find.textContaining('private-user'), findsNothing);
          expect(find.textContaining('Installation/'), findsNothing);
          expect(find.textContaining('ProtectedLink/'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final language in ['en', 'es']) {
    for (final dark in [false, true]) {
      testWidgets(
        'settings explain protected sharing restrictions and preserve manual preferences in $language, dark=$dark',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 1600);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          const protected = Account(
            id: 'protected',
            label: 'Protected',
            serverUrl: '',
            username: '',
            connectionType: AccountConnectionType.protectedSingleLink,
          );
          const manual = Account(
            id: 'manual',
            label: 'Manual',
            serverUrl: 'https://manual.example',
            username: 'test-user',
          );
          app.activeAccount = protected;
          app.showCopyLinkControls = true;
          app.showExportM3u = true;
          await tester.pumpWidget(
            host(const SettingsPage(), language: language, dark: dark),
          );
          await tester.ensureVisible(find.byKey(const Key('showExportM3u')));
          await tester.pumpAndSettle();
          SwitchListTile tile(String key) =>
              tester.widget<SwitchListTile>(find.byKey(Key(key)));
          final l10n = AppLocalizations.of(
            tester.element(find.byType(SettingsPage)),
          )!;
          expect(find.text(l10n.mediaActionsProtectedHelp), findsOneWidget);
          for (final key in ['showCopyLinkControls', 'showExportM3u']) {
            expect(tile(key).onChanged, isNull);
            expect(tile(key).value, isFalse);
          }
          expect(tile('showDownloadControls').onChanged, isNotNull);
          expect(app.showCopyLinkControls, isTrue);
          expect(app.showExportM3u, isTrue);

          app.activeAccount = manual;
          app.notifyListeners();
          await tester.pumpAndSettle();
          expect(find.text(l10n.mediaActionsProtectedHelp), findsNothing);
          for (final key in ['showCopyLinkControls', 'showExportM3u']) {
            expect(tile(key).onChanged, isNotNull);
            expect(tile(key).value, isTrue);
          }
          tile('showCopyLinkControls').onChanged!(false);
          tile('showExportM3u').onChanged!(false);
          await tester.pumpAndSettle();
          expect(app.showCopyLinkControls, isFalse);
          expect(app.showExportM3u, isFalse);

          app.activeAccount = protected;
          app.notifyListeners();
          await tester.pumpAndSettle();
          expect(find.text(l10n.mediaActionsProtectedHelp), findsOneWidget);
          expect(tile('showCopyLinkControls').onChanged, isNull);
          expect(tile('showExportM3u').onChanged, isNull);
          expect(tile('showDownloadControls').onChanged, isNotNull);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final protected in [false, true]) {
    testWidgets(
      'copy action visibility depends on account type: protected=$protected',
      (tester) async {
        app.activeAccount = Account(
          id: 'test',
          label: 'Test',
          serverUrl: '',
          username: '',
          connectionType: protected
              ? AccountConnectionType.protectedSingleLink
              : AccountConnectionType.xtream,
        );
        app.showCopyLinkControls = true;
        app.showDownloadControls = true;
        await tester.pumpWidget(
          host(
            const MediaActionMenu(
              media: MediaEntry(
                id: '100',
                title: 'Movie',
                kind: LibraryKind.movies,
              ),
            ),
          ),
        );
        await tester.tap(find.byType(PopupMenuButton<MediaAction>));
        await tester.pumpAndSettle();
        expect(
          find.text('Copy stream URL'),
          protected ? findsNothing : findsOneWidget,
        );
        expect(find.text('Download video'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
