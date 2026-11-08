import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/errors/app_exception.dart';
import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/models/protected_access_grant.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/storage/settings_store.dart';
import 'package:denuczi_tv/features/library/data/playlist_exporter.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/downloads/data/download_manager.dart';
import 'package:denuczi_tv/features/downloads/domain/download_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const manual = AccountCredentials(
    serverUrl: 'http://provider.example',
    username: 'manual',
    password: 'test-password',
    label: 'Manual',
  );
  const movie = MediaEntry(
    id: '100',
    title: 'Test movie',
    kind: LibraryKind.movies,
    containerExtension: 'mp4',
  );

  test('manual sharing and M3U export remain available while protected operations reject sharing', () async {
    final network = NetworkClient();
    addTearDown(network.dispose);
    final api = XtreamApi(network);
    final directory = await Directory.systemTemp.createTemp('sharing-policy-');
    addTearDown(() => directory.delete(recursive: true));
    final grant = ProtectedAccessGrant(accountId: 'protected');
    addTearDown(grant.dispose);
    final protected = AccountCredentials(
      serverUrl: manual.serverUrl,
      username: 'protected',
      password: 'private',
      label: 'Protected',
      protected: true,
      sourceScope: 'new',
      accessGrant: grant,
    );
    expect(
      api.shareableStreamUrl(manual, movie).path,
      '/movie/manual/test-password/100.mp4',
    );
    final exporter = PlaylistExporter(api);
    await exporter.exportToPath(
      destination: '${directory.path}/manual.m3u',
      credentials: manual,
      entries: [movie],
      categories: [],
      kind: LibraryKind.movies,
    );
    expect(
      await File('${directory.path}/manual.m3u').readAsString(),
      contains('/movie/manual/test-password/100.mp4'),
    );
    expect(
      () => api.shareableStreamUrl(protected, movie.withSourceScope('new')),
      throwsA(isA<AppException>()),
    );
    await expectLater(
      exporter.exportToPath(
        destination: '${directory.path}/protected.m3u',
        credentials: protected,
        entries: [movie.withSourceScope('new')],
        categories: [],
        kind: LibraryKind.movies,
      ),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      exporter.export(
        credentials: protected,
        entries: [],
        categories: [],
        kind: LibraryKind.live,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(await File('${directory.path}/protected.m3u').exists(), isFalse);
    expect(
      api.streamUrl(protected, movie.withSourceScope('new')).host,
      'provider.example',
    );
  });

  testWidgets(
    'the authorization timer revokes retained sessions at the deadline',
    (tester) async {
      var time = DateTime.utc(2099);
      final grant = ProtectedAccessGrant(
        accountId: 'protected',
        clock: () => time,
        expiresAt: time.add(const Duration(seconds: 5)),
      );
      addTearDown(grant.dispose);
      var stopped = 0;
      final subscription = grant.revocations.listen((_) => stopped++);
      addTearDown(subscription.cancel);
      expect(grant.usable, isTrue);
      time = time.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      expect(grant.usable, isFalse);
      expect(stopped, 1);
      grant.checkExpiry();
      await tester.pump();
      expect(stopped, 1);
    },
  );

  test('suspension cannot extend a credential snapshot beyond its expiry', () {
    var time = DateTime.utc(2099);
    final grant = ProtectedAccessGrant(
      accountId: 'protected',
      clock: () => time,
      expiresAt: time.add(const Duration(hours: 1)),
    );
    addTearDown(grant.dispose);
    time = time.add(const Duration(days: 3));
    expect(grant.usable, isFalse);
  });

  test('protected downloads use the ordinary UA and retain partial files on revocation', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final directory = await Directory.systemTemp.createTemp(
      'protected-transfer-',
    );
    final network = NetworkClient(userAgent: 'NormalTransfer/1');
    final manager = DownloadManager(
      network,
      SettingsStore(SharedPreferencesAsync()),
    );
    final grant = ProtectedAccessGrant(accountId: 'protected');
    final response = StreamController<Uint8List>();
    final requested = Completer<void>();
    addTearDown(() async {
      manager.dispose();
      network.dispose();
      grant.dispose();
      if (!response.isClosed) await response.close();
      await directory.delete(recursive: true);
    });
    network.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.headers['User-Agent'], 'NormalTransfer/1');
          expect(
            options.headers.values.join(' '),
            isNot(contains('Installation/')),
          );
          handler.resolve(
            Response<ResponseBody>(
              requestOptions: options,
              statusCode: 200,
              data: ResponseBody(
                response.stream,
                200,
                headers: {
                  'content-type': ['video/mp4'],
                  'content-length': ['8192'],
                },
              ),
              headers: Headers.fromMap({
                'content-type': ['video/mp4'],
                'content-length': ['8192'],
              }),
            ),
          );
          if (!requested.isCompleted) requested.complete();
        },
      ),
    );
    await manager.initialize();
    await manager.setDirectory(directory.path);
    final protected = AccountCredentials(
      serverUrl: 'http://provider.example',
      username: 'user',
      password: 'test-secret',
      label: 'Protected',
      protected: true,
      sourceScope: 'scope',
      accessGrant: grant,
    );
    expect(
      await manager.enqueue(
        credentials: protected,
        api: XtreamApi(network),
        media: [movie.withSourceScope('scope')],
        accountId: 'protected',
      ),
      1,
    );
    await requested.future;
    response.add(Uint8List.fromList(List.filled(4096, 42)));
    final partial = File('${manager.tasks.single.destination}.part');
    for (
      var i = 0;
      i < 100 && (!await partial.exists() || await partial.length() == 0);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(await partial.length(), greaterThan(0));
    grant.revoke();
    await response.close();
    for (
      var i = 0;
      i < 100 && manager.isTransferActive(manager.tasks.single.id);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(manager.tasks.single.status, DownloadStatus.cancelled);
    expect(await partial.exists(), isTrue);
    expect(manager.canRetry(manager.tasks.single.id), isFalse);
    await expectLater(
      manager.enqueue(
        credentials: protected,
        api: XtreamApi(network),
        media: [movie.withSourceScope('scope')],
        accountId: 'protected',
      ),
      throwsA(isA<AppException>()),
    );
  });
}
