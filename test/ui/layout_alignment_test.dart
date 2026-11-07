import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/models/app_controller.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/core/theme/app_theme.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:denuczi_tv/features/personal_library/application/personal_library_controller.dart';
import 'package:denuczi_tv/features/personal_library/data/sqlite_library_repository.dart';
import 'package:denuczi_tv/features/personal_library/presentation/my_library_page.dart';
import 'package:denuczi_tv/features/settings/presentation/settings_page.dart';
import 'package:denuczi_tv/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

AppController _controller({bool withLibrary = false}) {
  final network = NetworkClient();
  final preferences = SharedPreferencesAsync();
  return AppController(
    network: network,
    api: XtreamApi(network),
    accounts: AccountStore(preferences, const FlutterSecureStorage()),
    settings: SettingsStore(preferences),
    personalLibrary: withLibrary
        ? PersonalLibraryController(
            SqliteLibraryRepository(databasePath: ':memory:'),
          )
        : null,
  );
}

Widget _app(AppController controller, Widget page) {
  return ChangeNotifierProvider<AppController>.value(
    value: controller,
    child: MaterialApp(
      theme: AppTheme.light,
      locale: const Locale('es'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: page),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('language selector is centered like appearance', (tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller, const SettingsPage()));
    await tester.pumpAndSettle();

    final languageSelector = find.byKey(const Key('languageSelector'));
    final appearanceSelector = find.byType(SegmentedButton<ThemeMode>);
    expect(languageSelector, findsOneWidget);
    expect(appearanceSelector, findsOneWidget);

    final center = tester.getCenter(find.byType(SettingsPage)).dx;
    final languageCenter = tester.getCenter(languageSelector).dx;
    final appearanceCenter = tester.getCenter(appearanceSelector).dx;
    expect((languageCenter - center).abs(), lessThan(1));
    expect((appearanceCenter - center).abs(), lessThan(1));
  });

  testWidgets('language selector remains scrollable in a narrow window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller, const SettingsPage()));
    await tester.pumpAndSettle();

    final selector = find.byKey(const Key('languageSelector'));
    final scrollView = find.ancestor(
      of: selector,
      matching: find.byType(SingleChildScrollView),
    );
    expect(selector, findsOneWidget);
    expect(scrollView, findsOneWidget);
    expect(
      tester.getSize(selector).width,
      greaterThan(tester.getSize(scrollView).width),
    );
    final scrollable = find.descendant(
      of: scrollView,
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    expect(
      tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
      greaterThan(0),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('network identity actions share a size and alignment', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _controller();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller, const SettingsPage()));
    await tester.pumpAndSettle();

    final save = find.byKey(const Key('saveUserAgentButton'));
    final reset = find.byKey(const Key('resetUserAgentButton'));
    expect(tester.getSize(save), tester.getSize(reset));
    expect(tester.getTopLeft(save).dy, tester.getTopLeft(reset).dy);
    expect(tester.getTopLeft(save).dx, lessThan(tester.getTopLeft(reset).dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('personal library tabs remain scrollable in a narrow window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _controller(withLibrary: true);
    controller.activeAccount = const Account(
      id: 'test',
      label: 'Test account',
      serverUrl: 'https://provider.example',
      username: 'viewer',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller, const MyLibraryPage()));
    await tester.pumpAndSettle();

    final tabs = find.byKey(const Key('personalLibraryTabs'));
    final scrollView = find.ancestor(
      of: tabs,
      matching: find.byType(SingleChildScrollView),
    );
    expect(tabs, findsOneWidget);
    expect(scrollView, findsOneWidget);
    expect(
      tester.getSize(tabs).width,
      greaterThan(tester.getSize(scrollView).width),
    );
    final scrollable = find.descendant(
      of: scrollView,
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    expect(
      tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
      greaterThan(0),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('personal library navigation is horizontally centered', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _controller(withLibrary: true);
    controller.activeAccount = const Account(
      id: 'test',
      label: 'Test account',
      serverUrl: 'https://provider.example',
      username: 'viewer',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(controller, const MyLibraryPage()));
    await tester.pumpAndSettle();

    final tabs = find.byKey(const Key('personalLibraryTabs'));
    expect(tabs, findsOneWidget);
    final center = tester.getCenter(find.byType(MyLibraryPage)).dx;
    expect((tester.getCenter(tabs).dx - center).abs(), lessThan(1));
    expect(tester.takeException(), isNull);
  });
}
