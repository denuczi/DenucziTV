import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/models/app_controller.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:denuczi_tv/features/accounts/presentation/accounts_page.dart';
import 'package:denuczi_tv/features/connection/presentation/account_details_dialog.dart';
import 'package:denuczi_tv/features/connection/presentation/connect_dialog.dart';
import 'package:denuczi_tv/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

AppController createController() {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  final preferences = SharedPreferencesAsync();
  final network = NetworkClient();
  return AppController(
    network: network,
    api: XtreamApi(network),
    accounts: AccountStore(preferences, const FlutterSecureStorage()),
    settings: SettingsStore(preferences),
  );
}

void main() {
  testWidgets('account actions cannot open overlapping modal routes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final app = createController();
    addTearDown(app.dispose);
    const account = Account(
      id: 'account-1',
      label: 'Primary',
      serverUrl: 'https://provider.example',
      username: 'tester',
    );
    app.savedAccounts = [account];
    app.activeAccount = account;
    const status = AccountStatus(authorized: true, status: 'Active');
    app.accountStatus = status;
    app.accountStatuses[account.id] = status;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AccountsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Invoke the callback twice synchronously to model rapid desktop clicks.
    final addAccount = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Add account'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
    );
    addAccount.onPressed!();
    addAccount.onPressed!();
    await tester.pumpAndSettle();
    expect(find.byType(ConnectDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectDialog), findsNothing);

    final details = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('More details'),
        matching: find.byWidgetPredicate((widget) => widget is OutlinedButton),
      ),
    );
    details.onPressed!();
    details.onPressed!();
    await tester.pumpAndSettle();
    expect(find.byType(AccountDetailsDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountDetailsDialog), findsNothing);

    final removeAccount = tester.widget<TextButton>(
      find.ancestor(
        of: find.text('Remove saved account'),
        matching: find.byWidgetPredicate((widget) => widget is TextButton),
      ),
    );
    removeAccount.onPressed!();
    removeAccount.onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('Remove saved account?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(app.savedAccounts, contains(account));

    // The guard releases after a dialog closes and works for another action.
    addAccount.onPressed!();
    await tester.pumpAndSettle();
    expect(find.byType(ConnectDialog), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('provider metadata labels follow the selected language', (
    tester,
  ) async {
    final app = createController();
    addTearDown(app.dispose);
    app.activeAccount = const Account(
      id: 'account-1',
      label: 'Primary',
      serverUrl: 'https://provider.example',
      username: 'tester',
    );
    app.accountStatus = const AccountStatus(
      authorized: true,
      status: 'Active',
      isTrial: false,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: const MaterialApp(
          locale: Locale('es'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: AccountDetailsDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Activa'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == 'Estándar',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is SelectableText && widget.data == 'No disponible',
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });
}
