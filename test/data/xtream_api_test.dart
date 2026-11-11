import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/errors/app_exception.dart';
import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/models/protected_access_grant.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/core/network/user_agent.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';

void main() {
  const credentials = AccountCredentials(
    serverUrl: 'https://provider.example:8443',
    username: 'alice',
    password: 'secret',
    label: 'Test provider',
  );

  test(
    'authenticates using global User-Agent and encoded credentials',
    () async {
      final client = NetworkClient(userAgent: 'AppTest/2.0');
      late RequestOptions captured;
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = options;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'user_info': {'auth': 1, 'status': 'Active', 'exp_date': '0'},
                },
              ),
            );
          },
        ),
      );
      final result = await XtreamApi(client).authenticate(credentials);
      expect(result.authorized, isTrue);
      expect(captured.headers['user-agent'], 'AppTest/2.0');
      expect(captured.uri.queryParameters['username'], 'alice');
      expect(captured.uri.queryParameters['password'], 'secret');
      expect(captured.uri.path, '/player_api.php');
      client.dispose();
    },
  );

  test('uses a new User-Agent for subsequent requests', () async {
    final client = NetworkClient();
    final observed = <String>[];
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          observed.add(options.headers['user-agent'] as String);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'user_info': {'auth': 1, 'status': 'Active'},
              },
            ),
          );
        },
      ),
    );
    final api = XtreamApi(client);
    await api.authenticate(credentials);
    client.userAgent = 'CustomPlayer/8.3';
    await api.authenticate(credentials);
    expect(observed, [UserAgent.defaultValue, 'CustomPlayer/8.3']);
    expect(client.mediaHeaders['User-Agent'], 'CustomPlayer/8.3');
    expect(client.imageHeaders['User-Agent'], 'CustomPlayer/8.3');
    client.dispose();
  });

  test('rejects inactive accounts without leaking provider secrets', () async {
    final client = NetworkClient();
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'user_info': {'auth': 0, 'status': 'Disabled'},
            },
          ),
        ),
      ),
    );
    try {
      await XtreamApi(client).authenticate(credentials);
      fail('Authentication should have failed.');
    } on AppException catch (error) {
      expect(error.message, isNot(contains('secret')));
    } finally {
      client.dispose();
    }
  });

  test('loads VOD metadata from the dedicated details endpoint', () async {
    final client = NetworkClient();
    late RequestOptions captured;
    client.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'info': {
                  'plot': 'A sample movie',
                  'genre': 'Adventure',
                  'duration': '95 min',
                },
              },
            ),
          );
        },
      ),
    );
    final details = await XtreamApi(client).movieDetails(credentials, '123');
    expect(captured.uri.queryParameters['action'], 'get_vod_info');
    expect(captured.uri.queryParameters['vod_id'], '123');
    expect(details.plot, 'A sample movie');
    expect(details.genre, 'Adventure');
    client.dispose();
  });

  test(
    'skips entries missing IDs instead of failing the entire catalog',
    () async {
      final client = NetworkClient();
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: [
                {'stream_id': 123, 'name': 'Channel A', 'category_id': '1'},
                {'name': 'Missing ID'},
              ],
            ),
          ),
        ),
      );
      final results = await XtreamApi(client)
          .catalog(credentials, LibraryKind.live);
      expect(results.length, 1);
      expect(results.single.title, 'Channel A');
      client.dispose();
    },
  );

  test(
    'Live TV numbering is sequential, unique and ignores malformed rows',
    () async {
      final client = NetworkClient();
      addTearDown(client.dispose);
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: [
                {'stream_id': 10, 'name': 'News', 'category_id': 'news'},
                {'name': 'Invalid channel without ID'},
                {'stream_id': 42, 'name': 'HBO', 'category_id': 'films'},
                {'stream_id': 42, 'name': 'HBO copy', 'category_id': 'films'},
                {'stream_id': 9000, 'name': 'Sports', 'category_id': 'sports'},
              ],
            ),
          ),
        ),
      );
      final api = XtreamApi(client);
      final live = await api.catalog(credentials, LibraryKind.live);
      expect(live.map((entry) => entry.channelNumber).toList(), [1, 2, 3, 4]);
      expect(live.map((entry) => entry.id).toList(), [
        '10',
        '42',
        '42',
        '9000',
      ]);
      expect(live[1].withSourceScope('generation-1').channelNumber, 2);
      expect(live[2].withSourceScope('generation-2').channelNumber, 3);

      final movies = await api.catalog(credentials, LibraryKind.movies);
      final series = await api.catalog(credentials, LibraryKind.series);
      expect(movies.every((entry) => entry.channelNumber == null), isTrue);
      expect(series.every((entry) => entry.channelNumber == null), isTrue);
    },
  );

  test(
    'on-demand catalogues preserve the credential generation for every section',
    () async {
      final client = NetworkClient(userAgent: 'CatalogContract/1');
      addTearDown(client.dispose);
      client.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.headers['user-agent'], 'CatalogContract/1');
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: [
                  {'stream_id': 100, 'series_id': 100, 'name': 'Test content'},
                ],
              ),
            );
          },
        ),
      );
      final api = XtreamApi(client);
      for (final scope in ['', 'first-generation', 'second-generation']) {
        final grant = scope.isEmpty
            ? null
            : ProtectedAccessGrant(accountId: 'test');
        if (grant != null) addTearDown(grant.dispose);
        final connection = AccountCredentials(
          serverUrl: credentials.serverUrl,
          username: credentials.username,
          password: credentials.password,
          label: credentials.label,
          protected: scope.isNotEmpty,
          sourceScope: scope,
          accessGrant: grant,
        );
        for (final kind in LibraryKind.values) {
          final entries = await api.catalog(connection, kind);
          expect(entries.single.id, '100');
          expect(entries.single.kind, kind);
          expect(entries.single.sourceScope, scope);
        }
      }
    },
  );
}
