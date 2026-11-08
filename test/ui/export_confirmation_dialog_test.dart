import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/models/app_controller.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/core/theme/app_theme.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/library/presentation/library_page.dart';
import 'package:denuczi_tv/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _ExportController extends AppController {
  _ExportController({
    required super.network,
    required super.api,
    required super.accounts,
    required super.settings,
  });

  @override
  AccountCredentials get credentials => const AccountCredentials(
    serverUrl: 'https://provider.example',
    username: 'test-user',
    password: 'test-password',
    label: 'Test provider',
  );
}

void main() {
  for (final language in ['en', 'es']) {
    for (final width in [1600.0, 480.0]) {
      testWidgets('M3U confirmation is compact at $width in $language', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.empty();
        final preferences = SharedPreferencesAsync();
        final network = NetworkClient();
        final app = _ExportController(
          network: network,
          api: XtreamApi(network),
          accounts: AccountStore(preferences, const FlutterSecureStorage()),
          settings: SettingsStore(preferences),
        );
        addTearDown(app.dispose);
        app.activeAccount = const Account(
          id: 'test-account',
          label: 'Test provider',
          serverUrl: 'https://provider.example',
          username: 'test-user',
        );
        app.showExportM3u = true;
        app.entries = const [
          MediaEntry(
            id: 'test-channel',
            title: 'Test TV',
            kind: LibraryKind.live,
          ),
        ];

        await tester.pumpWidget(
          ChangeNotifierProvider<AppController>.value(
            value: app,
            child: MaterialApp(
              theme: AppTheme.dark,
              locale: Locale(language),
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: LibraryPage()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final label = language == 'es' ? 'Exportar M3U' : 'Export M3U';
        await tester.tap(
          width < 530 ? find.byTooltip(label) : find.text(label),
        );
        await tester.pumpAndSettle();

        final dialog = find.byType(AlertDialog);
        expect(dialog, findsOneWidget);
        final surface = find
            .descendant(of: dialog, matching: find.byType(Material))
            .first;
        final bounds = tester.getRect(surface);
        expect(bounds.width, lessThanOrEqualTo(440));
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(width));
        expect(tester.takeException(), isNull);

        await tester.tap(
          find.widgetWithText(
            TextButton,
            language == 'es' ? 'Cancelar' : 'Cancel',
          ),
        );
        await tester.pumpAndSettle();
        expect(dialog, findsNothing);
        expect(
          find.text(language == 'es' ? 'Exportar M3U' : 'Export M3U'),
          width < 530 ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
