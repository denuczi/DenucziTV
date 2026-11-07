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
  testWidgets('catalog header collapses without a layout exception', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
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
      id: 'example',
      label: 'Example',
      serverUrl: 'https://provider.example',
      username: 'viewer',
    );
    controller.kind = LibraryKind.movies;
    controller.entries = List.generate(
      400,
      (index) => MediaEntry(
        id: '$index',
        title: 'Example movie $index',
        kind: LibraryKind.movies,
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: LibraryPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1100));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('returnToTop')), findsOneWidget);

    // A bounded scroll extent keeps the draggable scrollbar useful even when
    // the provider returns many thousands of titles.
    final scrollView = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    final scroll = scrollView.controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Showing 200 of 400 titles'), findsOneWidget);
    final previousMaxExtent = scroll.position.maxScrollExtent;
    await tester.tap(find.byKey(const Key('loadMoreCatalog')));
    await tester.pumpAndSettle();

    // The footer is lazily built. Loading more items moves it below the old
    // viewport, so scroll to the new end before checking its content.
    expect(scroll.position.maxScrollExtent, greaterThan(previousMaxExtent));
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Showing 400 of 400 titles'), findsOneWidget);
    expect(find.byKey(const Key('loadMoreCatalog')), findsNothing);
  });
}
