import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/errors/app_exception.dart';
import 'package:denuczi_tv/core/models/account.dart';
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
}
