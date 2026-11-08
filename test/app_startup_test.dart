import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/models/app_controller.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:denuczi_tv/main.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets('desktop startup and settings', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Widget tests do not register platform implementations automatically.
    // Use the official in-memory backend for the asynchronous preferences API.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();

    final network = NetworkClient();
    final preferences = SharedPreferencesAsync();
    await preferences.setString('settings.user_agent', 'StartupTest/1.0');
    final controller = AppController(
      network: network,
      api: XtreamApi(network),
      accounts: AccountStore(preferences, const FlutterSecureStorage()),
      settings: SettingsStore(preferences),
    );
    await controller.initialize();

    expect(controller.initialized, isTrue);
    expect(network.userAgent, 'StartupTest/1.0');

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>(
        create: (_) => controller,
        child: const DenucziTVApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Your media, one place.'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Global User-Agent'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('globalUserAgent')),
      'StartupTest/2.0',
    );
    // Settings is scrollable; reveal the action before simulating a user tap.
    // A tap outside the test viewport does not invoke the save callback.
    final saveButton = find.text('Save User-Agent');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(network.userAgent, 'StartupTest/2.0');
    expect(
      await preferences.getString('settings.user_agent.custom.v2'),
      'StartupTest/2.0',
    );
    expect(
      await preferences.getString('settings.user_agent.mode.v2'),
      'custom',
    );
    expect(
      find.text('User-Agent saved for all new requests and streams.'),
      findsOneWidget,
    );
  });
}
