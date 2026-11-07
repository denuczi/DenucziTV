import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/models/app_controller.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _MemorySecrets implements AccountSecrets {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _TestApi extends XtreamApi {
  _TestApi(super.network);

  Completer<List<MediaEntry>>? pendingMovies;
  bool failAuthentication = false;
  int movieRequests = 0;

  @override
  Future<AccountStatus> authenticate(AccountCredentials credentials) async {
    if (failAuthentication) {
      throw StateError('Provider unavailable');
    }
    return const AccountStatus(authorized: true, status: 'Active');
  }

  @override
  Future<List<MediaCategory>> categories(
    AccountCredentials credentials,
    LibraryKind kind, {
    CancelToken? cancelToken,
  }) async => const <MediaCategory>[];

  @override
  Future<List<MediaEntry>> catalog(
    AccountCredentials credentials,
    LibraryKind kind, {
    CancelToken? cancelToken,
  }) async {
    if (kind == LibraryKind.movies) {
      movieRequests++;
      return pendingMovies?.future ?? const <MediaEntry>[];
    }
    return const <MediaEntry>[];
  }
}

const _login = AccountCredentials(
  serverUrl: 'https://example.org',
  username: 'demo',
  password: 'private-password',
  label: 'Demo',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test(
    'a populated provider response invalidates an empty filter cache',
    () async {
      final preferences = SharedPreferencesAsync();
      final network = NetworkClient();
      final api = _TestApi(network);
      final controller = AppController(
        network: network,
        api: api,
        accounts: AccountStore.withSecrets(preferences, _MemorySecrets()),
        settings: SettingsStore(preferences),
      );
      addTearDown(controller.dispose);

      expect(await controller.connect(_login), isTrue);
      final pending = Completer<List<MediaEntry>>();
      api.pendingMovies = pending;
      final loading = controller.selectKind(LibraryKind.movies);

      expect(controller.loading, isTrue);
      expect(controller.visibleEntries, isEmpty);
      pending.complete(const [
        MediaEntry(id: '1', title: 'Film One', kind: LibraryKind.movies),
        MediaEntry(id: '2', title: 'Film Two', kind: LibraryKind.movies),
      ]);
      await loading;

      expect(controller.loading, isFalse);
      expect(controller.visibleEntries.map((item) => item.title), [
        'Film One',
        'Film Two',
      ]);
      controller.setSearch('two');
      expect(controller.visibleEntries.single.title, 'Film Two');
      controller.setSearch('');
      expect(controller.visibleEntries.length, 2);

      await controller.selectKind(LibraryKind.live);
      await controller.selectKind(LibraryKind.movies);
      expect(
        api.movieRequests,
        1,
        reason: 'The loaded catalog should be reused',
      );
      expect(controller.visibleEntries.length, 2);
    },
  );

  test('the last successful account is reconnected after restart', () async {
    final preferences = SharedPreferencesAsync();
    final secrets = _MemorySecrets();
    final settings = SettingsStore(preferences);
    final networkA = NetworkClient();
    final first = AppController(
      network: networkA,
      api: _TestApi(networkA),
      accounts: AccountStore.withSecrets(preferences, secrets),
      settings: settings,
    );
    expect(await first.connect(_login), isTrue);
    final id = first.activeAccount!.id;
    expect(await settings.readActiveAccountId(), id);
    first.dispose();

    final networkB = NetworkClient();
    final restored = AppController(
      network: networkB,
      api: _TestApi(networkB),
      accounts: AccountStore.withSecrets(preferences, secrets),
      settings: settings,
    );
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(restored.automaticConnection, isNotNull);
    await restored.automaticConnection;

    expect(restored.activeAccount?.id, id);
    expect(restored.credentials?.password, _login.password);
    await restored.disconnect();
    expect(await settings.readActiveAccountId(), isNull);

    final networkC = NetworkClient();
    final disconnected = AppController(
      network: networkC,
      api: _TestApi(networkC),
      accounts: AccountStore.withSecrets(preferences, secrets),
      settings: settings,
    );
    addTearDown(disconnected.dispose);
    await disconnected.initialize();
    expect(
      disconnected.automaticConnection,
      isNull,
      reason: 'An explicit disconnect must survive application restart',
    );
    expect(disconnected.activeAccount, isNull);
  });

  test('offline reconnection leaves saved profiles available', () async {
    final preferences = SharedPreferencesAsync();
    final secrets = _MemorySecrets();
    final settings = SettingsStore(preferences);
    final networkA = NetworkClient();
    final first = AppController(
      network: networkA,
      api: _TestApi(networkA),
      accounts: AccountStore.withSecrets(preferences, secrets),
      settings: settings,
    );
    expect(await first.connect(_login), isTrue);
    first.dispose();

    final networkB = NetworkClient();
    final api = _TestApi(networkB)..failAuthentication = true;
    final restored = AppController(
      network: networkB,
      api: api,
      accounts: AccountStore.withSecrets(preferences, secrets),
      settings: settings,
    );
    addTearDown(restored.dispose);
    await restored.initialize();
    await restored.automaticConnection;

    expect(restored.activeAccount, isNull);
    expect(restored.restoringAccount, isFalse);
    expect(restored.savedAccounts, hasLength(1));
    expect(await settings.readActiveAccountId(), isNotNull);
  });
}
