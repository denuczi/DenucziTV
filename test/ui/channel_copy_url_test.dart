import 'dart:ui';

import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/models/app_controller.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/library/presentation/media_actions.dart';
import 'package:denuczi_tv/features/library/presentation/media_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _ConnectedController extends AppController {
  _ConnectedController(
    NetworkClient network,
    SharedPreferencesAsync preferences,
  ) : super(
        network: network,
        api: XtreamApi(network),
        accounts: AccountStore(preferences, const FlutterSecureStorage()),
        settings: SettingsStore(preferences),
      ) {
    showCopyLinkControls = true;
    activeAccount = const Account(
      id: 'account-1',
      label: 'Example provider',
      serverUrl: 'https://provider.example',
      username: 'demo',
    );
  }

  @override
  AccountCredentials? get credentials => const AccountCredentials(
    serverUrl: 'https://provider.example',
    username: 'demo',
    password: 'example-password',
    label: 'Example provider',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('copying a channel URL works after pointer leaves the card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    final network = NetworkClient();
    final app = _ConnectedController(network, SharedPreferencesAsync());
    addTearDown(app.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: app,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 190,
                height: 295,
                child: MediaCard(
                  entry: const MediaEntry(
                    id: '42',
                    title: 'Example channel',
                    kind: LibraryKind.live,
                  ),
                  network: network,
                  onOpen: () {},
                  showActions: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(
      tester.getCenter(find.byKey(const Key('mediaCardAction'))),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Media actions'));
    await tester.pumpAndSettle();
    expect(find.text('Copy stream URL'), findsOneWidget);

    // The menu is a separate route. Its button must survive losing card hover.
    await mouse.moveTo(const Offset(800, 600));
    await tester.pump();
    expect(find.byType(MediaActionMenu, skipOffstage: false), findsOneWidget);

    await tester.tap(find.text('Copy stream URL'));
    await tester.pumpAndSettle();
    expect(find.text('Copy a credential-bearing URL?'), findsOneWidget);
    expect(clipboardText, isNull);

    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    expect(
      clipboardText,
      'https://provider.example/live/demo/example-password/42.m3u8',
    );
    expect(
      find.text('Stream URL copied. Handle it as a password.'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Dismiss notification'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
