import 'package:flutter/material.dart';
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
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets('search and categories fade in only after catalog is available', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 840);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final preferences = SharedPreferencesAsync();
    final network = NetworkClient();
    final controller = AppController(
      network: network,
      api: XtreamApi(network),
      accounts: AccountStore(preferences, const FlutterSecureStorage()),
      settings: SettingsStore(preferences),
    );
    addTearDown(controller.dispose);
    controller.activeAccount = const Account(
      id: 'test-account',
      label: 'Test',
      serverUrl: 'https://example.org',
      username: 'user',
    );
    controller.kind = LibraryKind.movies;
    controller.loading = true;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: LibraryPage()),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('catalogFiltersPending')), findsOneWidget);
    expect(find.byKey(const Key('catalogSearchField')), findsNothing);
    expect(find.text('All'), findsNothing);

    controller.loading = false;
    controller.entries = const [
      MediaEntry(id: 'film', title: 'Example movie', kind: LibraryKind.movies),
    ];
    controller.setSearch('');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('catalogFiltersReady')), findsOneWidget);
    expect(find.byKey(const Key('catalogSearchField')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // An active search survives controller notifications and safely tears
    // down when the selected media kind changes.
    await tester.enterText(find.byKey(const Key('catalogSearchField')), 'c');
    await tester.pump();
    expect(find.byTooltip('Clear catalog search'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear catalog search'));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('catalogSearchField')))
          .controller
          ?.text,
      isEmpty,
    );
    await tester.enterText(find.byKey(const Key('catalogSearchField')), 'c');
    await tester.pump();
    controller.kind = LibraryKind.series;
    controller.setSearch('');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('catalogSearchField')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Hiding the search while its controller remains alive must not retain
    // a disposed widget listener.
    await tester.enterText(find.byKey(const Key('catalogSearchField')), 's');
    controller.loading = true;
    controller.setSearch('');
    // The loading indicator is indeterminate, so pumpAndSettle cannot finish.
    // Pump only the switcher's exit transition and inspect the new subtree.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const Key('catalogSearchField')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
