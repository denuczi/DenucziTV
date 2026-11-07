import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/features/library/data/playlist_exporter.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';

void main() {
  final credentials = AccountCredentials(
    serverUrl: 'https://provider.example',
    username: 'user',
    password: 'secret',
    label: 'Provider',
  );
  const media = [
    MediaEntry(id: '12', title: 'Movie', kind: LibraryKind.movies),
  ];

  test('playlist export refuses to erase a previously saved file', () async {
    final network = NetworkClient();
    addTearDown(network.dispose);
    final folder = await Directory.systemTemp.createTemp('open-stream-m3u-');
    addTearDown(() => folder.delete(recursive: true));
    final dest = File('${folder.path}/movies.m3u');
    await dest.writeAsString('previous export');
    final exporter = PlaylistExporter(XtreamApi(network));

    await expectLater(
      exporter.exportToPath(
        destination: dest.path,
        credentials: credentials,
        entries: media,
        categories: const [],
        kind: LibraryKind.movies,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await dest.readAsString(), 'previous export');
  });

  test('new playlist is written and its temporary file is removed', () async {
    final network = NetworkClient();
    addTearDown(network.dispose);
    final folder = await Directory.systemTemp.createTemp('open-stream-m3u-');
    addTearDown(() => folder.delete(recursive: true));
    final dest = File('${folder.path}/movies.m3u');
    final exporter = PlaylistExporter(XtreamApi(network));
    await exporter.exportToPath(
      destination: dest.path,
      credentials: credentials,
      entries: media,
      categories: const [],
      kind: LibraryKind.movies,
    );
    final content = await dest.readAsString();
    expect(content, startsWith('#EXTM3U\n'));
    expect(content, contains('Movie'));
    expect((await folder.list().toList()).length, 1);
  });
}
