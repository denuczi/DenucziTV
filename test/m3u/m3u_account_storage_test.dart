import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _MemorySecrets implements AccountSecrets {
  final values = <String, String>{};
  bool failDelete = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDelete) throw StateError('Simulated secure storage failure');
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
    id: 'm3u-1',
    label: 'My channels',
    serverUrl: '',
    username: '',
    connectionType: AccountConnectionType.m3u,
  );

  test('playlist URLs stay only in encrypted secret store', () async {
    final prefs = SharedPreferencesAsync();
    final secrets = _MemorySecrets();
    final store = AccountStore.withSecrets(prefs, secrets);
    const source = 'https://example.org/iptv.m3u?token=private-value';
    await store.savePlaylist(account, source);
    expect(await store.readPlaylistSource(account.id), source);
    expect(
      (await prefs.getString('accounts.list.v1'))!,
      isNot(contains(source)),
    );
    final restored = (await store.list()).single;
    expect(restored.isPlaylist, isTrue);
    expect(restored.serverUrl, isEmpty);
    expect(restored.username, isEmpty);
    expect(restored.toJson()['connectionType'], 'm3u');
  });

  test('deletion tombstone retries M3U source secret cleanup', () async {
    final prefs = SharedPreferencesAsync();
    final secrets = _MemorySecrets();
    final store = AccountStore.withSecrets(prefs, secrets);
    await store.savePlaylist(account, 'https://example.org/playlist.m3u');
    secrets.failDelete = true;
    await store.remove(account.id);
    expect(await store.list(), isEmpty);
    expect(secrets.values, contains('account.m3u-1.m3u.source.v1'));
    secrets.failDelete = false;
    await AccountStore.withSecrets(prefs, secrets).reconcilePendingDeletions();
    expect(secrets.values, isEmpty);
  });
}
