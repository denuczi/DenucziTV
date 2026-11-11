import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/models/app_controller.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/core/theme/app_theme.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/library/presentation/library_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  for (final kind in LibraryKind.values) {
    testWidgets('search remains visible and clearable after leaving '
        'and returning to ${kind.name}', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final preferences = SharedPreferencesAsync();
      final network = NetworkClient();
      final app = AppController(
        network: network,
        api: XtreamApi(network),
        accounts: AccountStore(preferences, const FlutterSecureStorage()),
        settings: SettingsStore(preferences),
      );
      addTearDown(app.dispose);
      app.activeAccount = const Account(
        id: 'test-account',
        label: 'Test',
        serverUrl: 'https://provider.example',
        username: 'test-user',
      );
      app.kind = kind;
      app.entries = [
        MediaEntry(id: '1', title: 'HBO One', kind: kind),
        MediaEntry(id: '2', title: 'HBO Two', kind: kind),
        MediaEntry(id: '3', title: 'Other', kind: kind),
      ];

      // Simulate DesktopShell replacing LibraryPage with SettingsPage.
      // A fresh page must reconstruct the text field from AppController.
      final inLibrary = ValueNotifier<bool>(true);
      addTearDown(inLibrary.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: app,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: inLibrary,
                builder: (context, active, child) =>
                    active ? const LibraryPage() : const Text('Settings'),
              ),
            ),
          ),
        ),
      );

      final searchField = find.byKey(const Key('catalogSearchField'));
      await tester.enterText(searchField, 'HBO');
      await tester.pump(const Duration(milliseconds: 200));
      expect(app.search, 'HBO');
      expect(app.visibleEntries.length, 2);

      inLibrary.value = false;
      await tester.pump();
      expect(find.byType(LibraryPage), findsNothing);
      expect(app.search, 'HBO');

      inLibrary.value = true;
      await tester.pump();
      expect(tester.widget<TextField>(searchField).controller?.text, 'HBO');
      expect(find.byTooltip('Clear catalog search'), findsOneWidget);
      expect(app.visibleEntries.length, 2);

      await tester.tap(find.byTooltip('Clear catalog search'));
      await tester.pump();
      expect(app.search, isEmpty);
      expect(app.visibleEntries.length, 3);
      expect(tester.widget<TextField>(searchField).controller?.text, isEmpty);
      expect(find.byTooltip('Clear catalog search'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
