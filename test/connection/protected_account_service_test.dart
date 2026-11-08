import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/errors/app_exception.dart';
import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/features/connection/application/protected_account_service.dart';
import 'package:denuczi_tv/features/connection/data/protected_link_resolver.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../helpers/protected_account_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesAsync preferences;
  late MemoryProtectedSecrets secrets;
  late AccountStore store;
  late NetworkClient network;
  late CatalogTestApi api;
  late ProtectedAccountService service;
  late DateTime time;
  late String destination;
  late List<String> identificationHeaders;
  late int probes;
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    preferences = SharedPreferencesAsync();
    secrets = MemoryProtectedSecrets();
    store = AccountStore.withSecrets(preferences, secrets);
    network = NetworkClient(userAgent: 'Custom/1');
    api = CatalogTestApi(network);
    time = DateTime.now().toUtc().add(const Duration(days: 2));
    destination = 'https://one.example/get.php?username=first&password=private&type=m3u_plus';
    identificationHeaders = [];
    probes = 0;
    service = ProtectedAccountService(
      store,
      api,
      network,
      clock: () => time,
      resolver: ProtectedLinkResolver(
        request: (uri, method, headers, timeout) async {
          probes++;
          expect(uri.toString(), 'https://link.example/permanent');
          identificationHeaders.add(headers['User-Agent']!);
          return LinkRedirectResponse(302, destination);
        },
      ),
    );
  });
  tearDown(() {
    service.dispose();
    network.dispose();
  });

  Future<PreparedProtectedAccount> register({
    LibraryKind initialKind = LibraryKind.live,
  }) => service.register(
    'Protected test',
    'https://link.example/permanent',
    initialKind: initialKind,
  );

  test(
    'installation UUID is generated once and survives store restart',
    () async {
      final ids = await Future.wait(
        List.generate(8, (_) => store.installationIdentity()),
      );
      expect(ids.toSet(), hasLength(1));
      expect(secrets.writes, 1);
      expect(
        ids.first,
        matches(r'^[0-9a-f-]{14}4[0-9a-f-]{4}[89ab][0-9a-f-]{16}$'),
      );
      final restarted = AccountStore.withSecrets(preferences, secrets);
      expect(await restarted.installationIdentity(), ids.first);
    },
  );

  test('protected secrets never enter public preferences; manual metadata remains intact', () async {
    const manual = Account(
      id: 'manual',
      label: 'Manual',
      serverUrl: 'https://manual.example',
      username: 'manual-user',
    );
    await store.save(manual, 'manual-password');
    final protected = await register();
    final raw = await preferences.getString('accounts.list.v1');
    for (final secret in [
      'link.example',
      'one.example',
      'first',
      'private',
      'Installation/',
    ]) {
      expect(raw, isNot(contains(secret)));
    }
    final profiles = await store.list();
    expect(
      profiles.singleWhere((account) => account.id == 'manual').connectionType,
      AccountConnectionType.xtream,
    );
    expect(await store.readPassword('manual'), 'manual-password');
    expect(
      profiles
          .singleWhere((account) => account.id == protected.account.id)
          .isProtected,
      isTrue,
    );
    expect(network.userAgent, 'Custom/1');
    expect(network.mediaHeaders['User-Agent'], 'Custom/1');
    expect(network.imageHeaders['User-Agent'], 'Custom/1');
  });

  test(
    'renewal keeps the account and identity but isolates reused media IDs',
    () async {
      final previous = await register(initialKind: LibraryKind.movies);
      final originalUrl = api.streamUrl(
        previous.secret.credentials!,
        previous.catalogs[LibraryKind.movies]!.entries.single,
      );
      time = time.add(const Duration(hours: 24));
      destination = 'http://different.example:8080/get.php?password=new-secret&username=other';
      final renewed = await service.renew(
        previous.account,
        initialKind: LibraryKind.movies,
      );
      expect(renewed.account.id, previous.account.id);
      expect(renewed.account.isProtected, isTrue);
      expect(identificationHeaders.toSet(), hasLength(1));
      expect(renewed.secret.sourceScope, isNot(previous.secret.sourceScope));
      final oldMedia = previous.catalogs[LibraryKind.movies]!.entries.single;
      final newMedia = renewed.catalogs[LibraryKind.movies]!.entries.single;
      expect(oldMedia.id, newMedia.id);
      expect(
        () => api.streamUrl(renewed.secret.credentials!, oldMedia),
        throwsA(isA<AppException>()),
      );
      expect(originalUrl.host, 'one.example');
      expect(previous.secret.credentials!.accessGrant!.usable, isTrue);
      expect(
        previous.secret.credentials!.accessGrant!.allowsNewSessions,
        isFalse,
      );
      expect(
        api.streamUrl(renewed.secret.credentials!, newMedia).host,
        'different.example',
      );
    },
  );

  test('even repeated credentials do not prove catalogue continuity', () async {
    final previous = await register();
    time = time.add(const Duration(hours: 24));
    final next = await service.renew(previous.account);
    expect(next.secret.sourceScope, isNot(previous.secret.sourceScope));
    expect(
      next.secret.credentials!.serverUrl,
      previous.secret.credentials!.serverUrl,
    );
    expect(previous.secret.credentials!.accessGrant!.usable, isTrue);
  });

  test('failed entry-section validation preserves the previous committed credentials', () async {
    final previous = await register(initialKind: LibraryKind.series);
    time = time.add(const Duration(hours: 24));
    destination = 'https://other.example/get.php?username=other&password=other';
    api.failKind = LibraryKind.series.name;
    await expectLater(
      service.renew(previous.account, initialKind: LibraryKind.series),
      throwsA(isA<AppException>()),
    );
    final saved = await store.readProtected(previous.account);
    expect(
      saved.credentials!.serverUrl,
      previous.secret.credentials!.serverUrl,
    );
    expect(saved.sourceScope, previous.secret.sourceScope);
    expect(saved.lastSuccess, previous.secret.lastSuccess);
    expect(service.isDue(saved), isFalse);
    expect(previous.secret.credentials!.accessGrant!.usable, isTrue);
  });

  test(
    'registration validates only Live TV and does not preload other sections',
    () async {
      api.failKind = LibraryKind.series.name;
      final prepared = await register();
      expect(api.authenticationRequests, 1);
      expect(api.categoryRequests, [LibraryKind.live]);
      expect(api.catalogRequests, [LibraryKind.live]);
      expect(prepared.catalogs.keys, [LibraryKind.live]);
      expect(prepared.secret.credentials!.accessGrant!.usable, isTrue);
      expect((await store.list()).single.id, prepared.account.id);
    },
  );

  test('cached reconnection loads its entry section without resolving the link again', () async {
    final previous = await register();
    api.categoryRequests.clear();
    api.catalogRequests.clear();
    final prepared = await service.connect(previous.account);
    expect(probes, 1);
    expect(api.categoryRequests, [LibraryKind.live]);
    expect(api.catalogRequests, [LibraryKind.live]);
    expect(prepared.catalogs.keys, [LibraryKind.live]);
    expect(prepared.secret.sourceScope, previous.secret.sourceScope);
  });

  test('renewal validates the requested section without waiting for unvisited sections', () async {
    final previous = await register();
    time = time.add(const Duration(hours: 24));
    api.categoryRequests.clear();
    api.catalogRequests.clear();
    api.failKind = LibraryKind.series.name;
    final prepared = await service.renew(
      previous.account,
      initialKind: LibraryKind.movies,
    );
    expect(api.categoryRequests, [LibraryKind.movies]);
    expect(api.catalogRequests, [LibraryKind.movies]);
    expect(prepared.catalogs.keys, [LibraryKind.movies]);
    expect(prepared.secret.sourceScope, isNot(previous.secret.sourceScope));
    expect(previous.secret.credentials!.accessGrant!.usable, isTrue);
    expect(
      previous.secret.credentials!.accessGrant!.allowsNewSessions,
      isFalse,
    );
  });

  test('invalid entry catalogue prevents account creation', () async {
    api.failKind = LibraryKind.live.name;
    await expectLater(register(), throwsA(isA<AppException>()));
    expect(await store.list(), isEmpty);
    expect(api.catalogRequests, [LibraryKind.live]);
  });

  test('concurrent renewals share one complete resolution', () async {
    final previous = await register();
    time = time.add(const Duration(hours: 24));
    api.block = Completer<void>();
    final a = service.renew(previous.account);
    final b = service.renew(previous.account);
    expect(identical(a, b), isTrue);
    api.block!.complete();
    await Future.wait([a, b]);
    expect(probes, 2);
  });

  test('link expiry revokes retained credential snapshots and clears the stored connection', () async {
    final expires = time.add(const Duration(seconds: 5));
    destination += '&dtv_expires=${expires.millisecondsSinceEpoch ~/ 1000}';
    final account = await register();
    final retained = account.secret.credentials!;
    // Compare with the integer-second expiry carried by the protocol.
    time = account.secret.expiresAt!;
    service.checkExpirations();
    expect(retained.accessGrant!.usable, isFalse);
    expect(
      () => api.streamUrl(
        retained,
        account.catalogs[LibraryKind.live]!.entries.single,
      ),
      throwsA(isA<AppException>()),
    );
    await service.expire(account.account);
    final saved = await store.readProtected(account.account);
    expect(saved.credentials, isNull);
    expect(saved.originalUrl, 'https://link.example/permanent');
    expect((await store.list()).single.id, account.account.id);
  });

  test('renaming never replaces the committed secure connection', () async {
    final account = await register();
    time = time.add(const Duration(hours: 24));
    destination = 'https://new.example/get.php?username=new&password=new';
    final renewed = await service.renew(account.account);
    final writes = secrets.writes;
    await store.renameProtected(account.account, 'Renamed');
    expect(secrets.writes, writes);
    final stored = await store.readProtected(account.account);
    expect(stored.sourceScope, renewed.secret.sourceScope);
    expect(stored.credentials!.serverUrl, 'https://new.example');
    expect((await store.list()).single.label, 'Renamed');
  });

  test(
    'expiry cleanup does not overwrite a later valid authorization',
    () async {
      final account = await register();
      final committed = await store.expireProtected(account.account, time);
      expect(committed.credentials, isNotNull);
      expect(committed.sourceScope, account.secret.sourceScope);
    },
  );

  test(
    'corrupt secure expiry fails closed instead of becoming unlimited access',
    () async {
      final account = await register();
      final key = 'account.${account.account.id}.protected.v1';
      final state = jsonDecode(secrets.values[key]!) as Map<String, dynamic>;
      state['expiresAt'] = 'corrupt';
      secrets.values[key] = jsonEncode(state);
      await expectLater(
        store.readProtected(account.account),
        throwsA(isA<AppException>()),
      );
    },
  );

  test('Xtream expiry never substitutes for missing dtv_expires', () async {
    final account = await register();
    expect(account.status.expiration, isNotNull);
    expect(account.secret.expiresAt, isNull);
  });

  test('an expired account can receive a fresh validated authorization', () async {
    destination +=
        '&dtv_expires=${time.add(const Duration(seconds: 5)).millisecondsSinceEpoch ~/ 1000}';
    final account = await register();
    time = time.add(const Duration(minutes: 1));
    await service.expire(account.account);
    destination =
        'https://new.example/get.php?username=new&password=new&dtv_expires=${time.add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000}';
    final recovered = await service.renew(account.account);
    expect(recovered.secret.credentials!.accessGrant!.usable, isTrue);
    expect(recovered.account.id, account.account.id);
    expect(recovered.secret.sourceScope, isNot(account.secret.sourceScope));
  });

  test('secure-store failure cannot publish a new account', () async {
    secrets.failWrites = true;
    await expectLater(register(), throwsA(anything));
    expect(await store.list(), isEmpty);
  });

  test('a persisted attempt survives restart and prevents immediate automatic retries', () async {
    final account = await register();
    time = time.add(const Duration(hours: 24));
    api.rejectAuthentication = true;
    await expectLater(service.renew(account.account), throwsA(anything));
    final restarted = ProtectedAccountService(
      store,
      api,
      network,
      clock: () => time,
    );
    addTearDown(restarted.dispose);
    expect(
      restarted.isDue(await store.readProtected(account.account)),
      isFalse,
    );
  });
}
