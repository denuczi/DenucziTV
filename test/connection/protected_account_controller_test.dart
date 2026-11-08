import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/models/app_controller.dart';
import 'package:denuczi_tv/core/models/protected_account.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/features/connection/data/protected_link_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../helpers/protected_account_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppController app;
  late AccountStore store;
  late MemoryProtectedSecrets secrets;
  late DateTime time;
  late String destination;
  void createController() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final preferences = SharedPreferencesAsync();
    final network = NetworkClient();
    secrets = MemoryProtectedSecrets();
    store = AccountStore.withSecrets(preferences, secrets);
    time = DateTime.now().toUtc().add(const Duration(days: 2));
    destination = 'https://one.example/get.php?username=first&password=private';
    app = AppController(
      network: network,
      api: CatalogTestApi(network),
      accounts: store,
      settings: SettingsStore(preferences),
      clock: () => time,
      protectedLinkResolver: ProtectedLinkResolver(
        request: (uri, method, headers, timeout) async =>
            LinkRedirectResponse(302, destination),
      ),
    );
  }

  group('account controller', () {
    setUp(createController);
    tearDown(() => app.dispose());

    test('manual and protected accounts coexist without changing manual sharing capabilities', () async {
      app.showExportM3u = true;
      app.showCopyLinkControls = true;
      const input = AccountCredentials(
        serverUrl: 'https://manual.example',
        username: 'manual-user',
        password: 'manual-secret',
        label: 'Manual',
      );
      expect(await app.connect(input), isTrue);
      final manual = app.activeAccount!;
      expect(app.canShareLinks, isTrue);
      expect(app.exportM3uAvailable, isTrue);
      expect(app.copyLinksAvailable, isTrue);
      expect(
        await app.connectProtected(
          'Protected',
          'https://link.example/permanent',
        ),
        isTrue,
      );
      final protected = app.activeAccount!;
      expect(app.canShareLinks, isFalse);
      expect(app.exportM3uAvailable, isFalse);
      expect(app.copyLinksAvailable, isFalse);
      await app.connectSaved(manual);
      expect(app.activeAccount!.id, manual.id);
      expect(app.activeAccount!.isProtected, isFalse);
      expect(app.canShareLinks, isTrue);
      expect(app.exportM3uAvailable, isTrue);
      expect(app.copyLinksAvailable, isTrue);
      expect(await app.connect(input, existingId: protected.id), isFalse);
      expect(
        (await store.list())
            .singleWhere((item) => item.id == protected.id)
            .isProtected,
        isTrue,
      );
    });

    test('validated replacement clears obsolete filters and isolates reused IDs', () async {
      expect(
        await app.connectProtected(
          'Protected',
          'https://link.example/permanent',
        ),
        isTrue,
      );
      final account = app.activeAccount!;
      final oldConnection = app.credentials!;
      final oldEntry = app.entries.single;
      final originalUrl = app.api.streamUrl(oldConnection, oldEntry);
      app.categoryId = 'old-category';
      app.search = 'old-search';
      time = time.add(const Duration(days: 1));
      destination =
          'http://different.example:8080/get.php?username=second&password=new';
      await app.refreshProtectedAccount(account);
      expect(app.activeAccount!.id, account.id);
      expect(app.categoryId, isNull);
      expect(app.search, isEmpty);
      expect(app.categories.single.id, 'second');
      expect(app.entries.single.id, oldEntry.id);
      expect(app.canUseMedia(oldEntry), isFalse);
      expect(app.canUseMedia(app.entries.single), isTrue);
      // The old playback/download snapshot remains usable until its own expiry.
      expect(oldConnection.accessGrant!.usable, isTrue);
      expect(originalUrl.host, 'one.example');
      expect(oldConnection.accessGrant!.allowsNewSessions, isFalse);
    });

    test('failed refresh leaves the valid runtime catalogue and credentials intact', () async {
      expect(
        await app.connectProtected(
          'Protected',
          'https://link.example/permanent',
        ),
        isTrue,
      );
      final account = app.activeAccount!;
      final previous = app.credentials;
      final previousEntries = app.entries;
      time = time.add(const Duration(days: 1));
      destination = 'https://invalid.example/not-xtream';
      await app.refreshProtectedAccount(account);
      expect(app.credentials, same(previous));
      expect(app.entries, same(previousEntries));
      expect(app.protectedSyncStates[account.id], ProtectedSyncState.failed);
    });

    test('resume revokes access even while secure-store cleanup is unavailable', () async {
      destination +=
          '&dtv_expires=${time.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000}';
      expect(
        await app.connectProtected(
          'Protected',
          'https://link.example/permanent',
        ),
        isTrue,
      );
      final retained = app.credentials!;
      secrets.failWrites = true;
      time = time.add(const Duration(days: 3));
      app.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);
      expect(retained.accessGrant!.usable, isFalse);
      expect(app.credentials, isNull);
      expect(app.entries, isEmpty);
      expect(app.savedAccounts.single.isProtected, isTrue);
      expect(app.error, isNot(contains('private')));
    });

    test('startup refuses persisted expired credentials without requesting Xtream', () async {
      destination +=
          '&dtv_expires=${time.add(const Duration(seconds: 5)).millisecondsSinceEpoch ~/ 1000}';
      expect(
        await app.connectProtected(
          'Protected',
          'https://link.example/permanent',
        ),
        isTrue,
      );
      final account = app.activeAccount!;
      await app.disconnect();
      time = time.add(const Duration(days: 2));
      await app.connectSaved(account);
      expect(app.credentials, isNull);
      expect(app.entries, isEmpty);
      expect((await store.readProtected(account)).credentials, isNull);
      expect((await store.list()).single.id, account.id);
    });
  });

  testWidgets(
    'expiry withdraws catalogue and snapshots at the exact deadline',
    (tester) async {
      // Futures and timers must be created inside the test's fake-async zone.
      createController();
      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>(
          create: (_) => app,
          lazy: false,
          child: const SizedBox.shrink(),
        ),
      );
      final expires = DateTime.fromMillisecondsSinceEpoch(
        (time.add(const Duration(seconds: 10)).millisecondsSinceEpoch ~/ 1000) *
            1000,
        isUtc: true,
      );
      destination += '&dtv_expires=${expires.millisecondsSinceEpoch ~/ 1000}';
      expect(
        await app.connectProtected(
          'Protected',
          'https://link.example/permanent',
        ),
        isTrue,
      );
      final account = app.activeAccount!;
      final retained = app.credentials!;
      final originalEntry = app.entries.single;
      final delay = expires.difference(time);
      const lastInstant = Duration(microseconds: 1);
      time = expires.subtract(lastInstant);
      await tester.pump(delay - lastInstant);
      expect(retained.accessGrant!.usable, isTrue);
      expect(app.credentials, same(retained));
      expect(app.entries, isNotEmpty);
      time = expires;
      await tester.pump(lastInstant);
      expect(retained.accessGrant!.usable, isFalse);
      expect(app.credentials, isNull);
      expect(app.entries, isEmpty);
      expect(app.categories, isEmpty);
      expect(app.canUseMedia(originalEntry), isFalse);
      expect(app.savedAccounts.single.id, account.id);
      expect(app.expiredProtectedAccounts, contains(account.id));
    },
  );
}
