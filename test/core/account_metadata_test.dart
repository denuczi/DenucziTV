import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/core/models/account.dart';
import 'package:denuczi_tv/core/network/network_client.dart';
import 'package:denuczi_tv/features/library/data/xtream_api.dart';

void main() {
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
