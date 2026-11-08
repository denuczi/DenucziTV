import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';

void main() {
  Future<AccountStatus> authenticateWith(Map<String, Object?> info) async {
    final network = NetworkClient();
    addTearDown(network.dispose);
    network.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'user_info': {'auth': 1, 'status': 'Active', ...info},
            },
          ),
        ),
      ),
    );
    return XtreamApi(network).authenticate(
      const AccountCredentials(
        serverUrl: 'https://provider.example',
        username: 'test-user',
        password: 'test-password',
        label: 'Test provider',
      ),
    );
  }

  test(
    'creation and expiration remain independent through the cache',
    () async {
      for (final createdAt in ['1609459200', 1609459200]) {
        final status = await authenticateWith({
          'created_at': createdAt,
          'exp_date': '4070908800',
        });
        expect(status.createdAt, DateTime.utc(2021, 1, 1));
        expect(status.expiration, DateTime.utc(2099, 1, 1));

        final restored = AccountStatus.fromJson(status.toJson());
        expect(restored.createdAt, status.createdAt);
        expect(restored.expiration, status.expiration);
      }
    },
  );

  test(
    'missing creation dates are not replaced with expiration dates',
    () async {
      for (final createdAt in [null, '', 'invalid', '0']) {
        final status = await authenticateWith({
          'created_at': createdAt,
          'exp_date': '4070908800',
        });
        expect(status.createdAt, isNull);
        expect(status.expiration, DateTime.utc(2099, 1, 1));
      }
    },
  );

  test(
    'identical provider dates are preserved without inventing a date',
    () async {
      final status = await authenticateWith({
        'created_at': '4070908800',
        'exp_date': '4070908800',
      });
      expect(status.createdAt, DateTime.utc(2099, 1, 1));
      expect(status.expiration, DateTime.utc(2099, 1, 1));
    },
  );

  test(
    'reads optional account information without exposing passwords',
    () async {
      final network = NetworkClient();
      network.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'user_info': {
                  'auth': 1,
                  'status': 'Active',
                  'created_at': '1609459200',
                  'exp_date': '0',
                  'active_cons': '1',
                  'max_connections': '3',
                  'is_trial': '0',
                  'allowed_output_formats': ['m3u8', 'ts'],
                },
                'server_info': {'timezone': 'America/Argentina/Buenos_Aires'},
              },
            ),
          ),
        ),
      );
      const credentials = AccountCredentials(
        serverUrl: 'https://provider.example',
        username: 'alice',
        password: 'secret',
        label: 'Primary',
      );
      final status = await XtreamApi(network).authenticate(credentials);
      expect(status.createdAt, DateTime.utc(2021, 1, 1));
      expect(status.createdAt?.isUtc, isTrue);
      expect(status.expiration, isNull);
      expect(status.activeConnections, 1);
      expect(status.maxConnections, 3);
      expect(status.isTrial, isFalse);
      expect(status.allowedFormats, ['m3u8', 'ts']);
      expect(status.serverTimezone, 'America/Argentina/Buenos_Aires');
      network.dispose();
    },
  );
}
