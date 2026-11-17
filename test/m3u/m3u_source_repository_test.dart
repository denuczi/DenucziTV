import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/errors/app_exception.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/features/m3u/data/m3u_source_repository.dart';

void main() {
  late HttpServer server;
  late NetworkClient network;
  late M3uSourceRepository repository;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    network = NetworkClient(dio: Dio());
    repository = M3uSourceRepository(network);
  });

  tearDown(() async {
    network.dispose();
    await server.close(force: true);
  });

  void mockStreamedResponse(
    Stream<Uint8List> body, {
    Map<String, List<String>> headers = const {},
  }) {
    network.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<ResponseBody>(
              requestOptions: options,
              statusCode: HttpStatus.ok,
              headers: Headers.fromMap(headers),
              data: ResponseBody(body, HttpStatus.ok, headers: headers),
            ),
          );
        },
      ),
    );
  }

  test('loads a remote M3U through four redirects', () async {
    server.listen((request) {
      final current = int.tryParse(request.uri.pathSegments.last) ?? 4;
      if (current < 4) {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(
          HttpHeaders.locationHeader,
          '/${current + 1}',
        );
      } else {
        request.response.write(
          '#EXTM3U\n#EXTINF:-1,News\nhttps://example.org/live.m3u8\n',
        );
      }
      request.response.close();
    });
    final result = await repository.import('http://127.0.0.1:${server.port}/0');
    expect(result.entries, hasLength(1));
  });

  test('rejects the fifth redirect', () async {
    server.listen((request) {
      final current = int.tryParse(request.uri.pathSegments.last) ?? 0;
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set(
        HttpHeaders.locationHeader,
        '/${current + 1}',
      );
      request.response.close();
    });
    await expectLater(
      repository.import('http://127.0.0.1:${server.port}/0'),
      throwsA(isA<Exception>()),
    );
  });

  test('rejects a declared content length over the size limit', () async {
    final advertisedLength = M3uSourceRepository.maxBytes + 1;
    mockStreamedResponse(
      const Stream<Uint8List>.empty(),
      headers: {
        Headers.contentLengthHeader: ['$advertisedLength'],
      },
    );

    await expectLater(
      repository.import('https://example.org/large.m3u'),
      throwsA(
        isA<AppException>().having(
          (error) => error.message,
          'message',
          'The remote playlist is too large.',
        ),
      ),
    );
  });

  test('rejects a stream exceeding the limit without content length', () async {
    final chunk = Uint8List(1024 * 1024);
    mockStreamedResponse(
      Stream<Uint8List>.fromIterable(List<Uint8List>.filled(17, chunk)),
    );

    await expectLater(
      repository.import('https://example.org/large-stream.m3u'),
      throwsA(
        isA<AppException>().having(
          (error) => error.message,
          'message',
          'The remote playlist is too large.',
        ),
      ),
    );
  });

  test('reads a local M3U file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'denuczi-m3u-test-',
    );
    try {
      final file = File('${directory.path}/channels.m3u');
      await file.writeAsString(
        '#EXTM3U\n#EXTINF:-1,News\nhttps://example.org/stream.ts\n',
      );
      final playlist = await repository.import(file.path);
      expect(playlist.entries.single.title, 'News');
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
