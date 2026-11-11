import 'dart:convert';
import 'dart:io';

import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/personal_library/application/library_artwork_cache.dart';
import 'package:denuczi_tv/features/personal_library/domain/library_item.dart';
import 'package:flutter_test/flutter_test.dart';

// A tiny real PNG avoids mocking Flutter image decoding or network internals.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/XgAAAABJRU5ErkJggg==',
);

void main() {
  late Directory directory;
  late HttpServer server;
  late NetworkClient network;
  var requests = 0;
  var clock = DateTime.utc(2026, 11, 11);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('denuczitv-artwork-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    requests = 0;
    clock = DateTime.utc(2026, 11, 11);
    server.listen((request) {
      requests++;
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(
        request.uri.path == '/invalid.png'
            ? [0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0, 0, 0, 0, 0]
            : _png,
      );
      request.response.close();
    });
    network = NetworkClient();
  });

  tearDown(() async {
    network.dispose();
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  MediaEntry channel() => MediaEntry(
    id: '42',
    title: 'News',
    kind: LibraryKind.live,
    imageUrl: 'http://127.0.0.1:${server.port}/cover.png',
  );

  test(
    'survives restart, isolates accounts and expires after three days',
    () async {
      final item = LibraryItem.fromMedia(accountId: 'a', media: channel());
      final cache = LibraryArtworkCache(
        network,
        directory: directory,
        clock: () => clock,
      );
      final first = await cache.getOrLoad(
        item,
        resolveUrl: () async => channel().imageUrl,
      );
      expect(first, isNotNull);
      expect(await first!.exists(), isTrue);
      expect(requests, 1);

      final restarted = LibraryArtworkCache(
        network,
        directory: directory,
        clock: () => clock,
      );
      expect(await restarted.getOrLoad(item), isNotNull);
      expect(requests, 1);
      final other = LibraryItem.fromMedia(accountId: 'b', media: channel());
      expect(await restarted.getOrLoad(other), isNull);
      clock = clock.add(const Duration(days: 3, seconds: 1));
      expect(await restarted.getOrLoad(item), isNull);
      final renewed = await restarted.getOrLoad(
        item,
        resolveUrl: () async => channel().imageUrl,
      );
      expect(renewed, isNotNull);
      expect(requests, 2);
    },
  );

  test(
    'removes the cached image and all data when an account is deleted',
    () async {
      final cache = LibraryArtworkCache(network, directory: directory);
      final item = LibraryItem.fromMedia(accountId: 'a', media: channel());
      final cover = await cache.getOrLoad(
        item,
        resolveUrl: () async => channel().imageUrl,
      );
      expect(cover, isNotNull);
      await cache.removeItem(item);
      expect(await cover!.exists(), isFalse);
      await cache.warm('a', channel());
      await cache.removeAccount('a');
      expect(await cache.getOrLoad(item), isNull);
    },
  );

  test(
    'rejects malformed binary artwork without retaining partial files',
    () async {
      final cache = LibraryArtworkCache(network, directory: directory);
      final item = LibraryItem.fromMedia(
        accountId: 'a',
        media: MediaEntry(
          id: 'invalid',
          title: 'Invalid image',
          kind: LibraryKind.live,
          imageUrl: 'http://127.0.0.1:${server.port}/invalid.png',
        ),
      );

      final image = await cache.getOrLoad(
        item,
        resolveUrl: () async => 'http://127.0.0.1:${server.port}/invalid.png',
      );
      expect(image, isNull);
      expect(requests, 1);
      expect(
        directory.listSync(recursive: true).whereType<File>().toList(),
        isEmpty,
      );
    },
  );

  test('never saves URLs or tokens into cache file names', () async {
    final cache = LibraryArtworkCache(network, directory: directory);
    final entry = channel().withSourceScope('scope-with-secret');
    final item = LibraryItem.fromMedia(
      accountId: 'account-private',
      media: entry,
    );
    final cover = await cache.getOrLoad(
      item,
      resolveUrl: () async => entry.imageUrl,
    );
    expect(cover, isNotNull);
    expect(cover!.path, isNot(contains('account-private')));
    expect(cover.path, isNot(contains('scope-with-secret')));
    expect(cover.path, isNot(contains('http')));
  });
}
