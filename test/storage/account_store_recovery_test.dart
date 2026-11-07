import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class FakeAccountSecrets implements AccountSecrets {
  final Map<String, String> values = {};
  bool failDelete = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDelete) {
      throw StateError('Simulated secure store outage');
    }
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  const account = Account(
    id: 'account-1',
    label: 'Provider',
    serverUrl: 'https://example.test',
    username: 'subscriber',
  );

  test('failed credential deletion never leaves a visible account without its secret', () async {
    final preferences = SharedPreferencesAsync();
    final secrets = FakeAccountSecrets();
    final store = AccountStore.withSecrets(preferences, secrets);

    await store.save(account, 'secret');
    expect(await store.readPassword(account.id), 'secret');

    secrets.failDelete = true;
    await store.remove(account.id);

    expect(await store.list(), isEmpty);
    expect(secrets.values, contains('account.account-1.password'));
    expect(
      await preferences.getStringList('accounts.pending_secret_deletion.v1'),
      contains(account.id),
    );

    secrets.failDelete = false;
    final restartedStore = AccountStore.withSecrets(preferences, secrets);
    await restartedStore.reconcilePendingDeletions();
    expect(secrets.values, isEmpty);
    expect(await restartedStore.list(), isEmpty);
    expect(
      await preferences.getStringList('accounts.pending_secret_deletion.v1'),
      isEmpty,
    );
  });

  test(
    'a visible account is protected from an obsolete deletion marker',
    () async {
      final preferences = SharedPreferencesAsync();
      final secrets = FakeAccountSecrets();
      final store = AccountStore.withSecrets(preferences, secrets);
      await store.save(account, 'secret');
      await preferences.setStringList('accounts.pending_secret_deletion.v1', [
        account.id,
      ]);

      await store.reconcilePendingDeletions();
      expect(await store.readPassword(account.id), 'secret');
      expect(
        await preferences.getStringList('accounts.pending_secret_deletion.v1'),
        isEmpty,
      );
    },
  );
}
