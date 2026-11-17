import 'dart:io';

import 'package:denuczi_tv/core/models/app_controller.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/account_store.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

class _MemorySecrets implements AccountSecrets {
  final values = <String, String>{};

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test(
    'M3U account loads live and movies without Xtream credentials',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'denuczi-m3u-app-',
      );
      final file = File('${directory.path}/playlist.m3u');
      await file.writeAsString('''#EXTM3U
#EXTINF:-1 group-title="News",Channel
https://media.example.org/live.m3u8|user-agent=Demo%20Browser
#EXTINF:-1 group-title="Movies",Film
https://media.example.org/film.mp4
''');
      final preferences = SharedPreferencesAsync();
      final secrets = _MemorySecrets();
      final network = NetworkClient();
      final controller = AppController(
        network: network,
        api: XtreamApi(network),
        accounts: AccountStore.withSecrets(preferences, secrets),
        settings: SettingsStore(preferences),
      );
      try {
        expect(
          await controller.connectPlaylist(file.path, 'My Playlist'),
          isTrue,
        );
        expect(controller.credentials, isNull);
        expect(controller.isM3uAccount, isTrue);
        expect(controller.canShareLinks, isFalse);
        expect(controller.entries, hasLength(1));
        final live = controller.entries.single;
        expect(live.kind, LibraryKind.live);
        expect(controller.canUseMedia(live), isTrue);
        expect(
          controller.playlistStream(live)?.headers['User-Agent'],
          'Demo Browser',
        );
        expect(controller.playlistChannels.single.id, live.id);

        await controller.selectKind(LibraryKind.movies);
        expect(controller.entries, hasLength(1));
        expect(controller.entries.single.title, 'Film');
        await controller.selectKind(LibraryKind.series);
        expect(controller.entries, isEmpty);
        expect(controller.canUseMedia(live), isTrue);

        await controller.disconnect();
        expect(controller.canUseMedia(live), isFalse);
      } finally {
        controller.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  test('saved M3U account reconnects from secure source', () async {
    final directory = await Directory.systemTemp.createTemp(
      'denuczi-m3u-restore-',
    );
    final file = File('${directory.path}/playlist.m3u');
    await file.writeAsString(
      '#EXTM3U\n#EXTINF:-1,News\nhttps://example.org/news.ts\n',
    );
    final preferences = SharedPreferencesAsync();
    final secrets = _MemorySecrets();
    final store = AccountStore.withSecrets(preferences, secrets);
    final settings = SettingsStore(preferences);
    final firstNetwork = NetworkClient();
    final first = AppController(
      network: firstNetwork,
      api: XtreamApi(firstNetwork),
      accounts: store,
      settings: settings,
    );
    try {
      expect(await first.connectPlaylist(file.path, 'News'), isTrue);
      final id = first.activeAccount!.id;
      await first.disconnect();
      final secondNetwork = NetworkClient();
      final second = AppController(
        network: secondNetwork,
        api: XtreamApi(secondNetwork),
        accounts: AccountStore.withSecrets(preferences, secrets),
        settings: settings,
      );
      try {
        final saved = (await store.list()).single;
        await second.connectSaved(saved);
        expect(second.activeAccount?.id, id);
        expect(second.isM3uAccount, isTrue);
        expect(second.entries.single.title, 'News');
      } finally {
        second.dispose();
      }
    } finally {
      first.dispose();
      await directory.delete(recursive: true);
    }
  });
}
