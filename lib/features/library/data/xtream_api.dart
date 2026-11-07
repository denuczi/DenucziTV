import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/models/account.dart';
import '../../../core/network/network_client.dart';
import '../../../core/network/server_address.dart';
import '../domain/media_models.dart';

/// A typed client for the commonly implemented Xtream player API endpoints.
///
/// Provider responses are inconsistent; invalid individual catalog entries are
/// skipped, while invalid top-level responses fail explicitly.
class XtreamApi {
  XtreamApi(this._network);

  final NetworkClient _network;

  Future<Object?> _request(
    AccountCredentials credentials, {
    String? action,
    Map<String, String> arguments = const {},
    CancelToken? cancelToken,
  }) async {
    final base = ServerAddress.parse(credentials.serverUrl);
    final url = ServerAddress.api(base, {
      'username': credentials.username,
      'password': credentials.password,
      'action': ?action,
      ...arguments,
    });
    try {
      final response = await _network.dio.getUri<Object?>(
        url,
        cancelToken: cancelToken,
        options: Options(responseType: ResponseType.json),
      );
      if ((response.statusCode ?? 500) >= 300) {
        throw const AppException(
          'The provider redirected the API request. Verify the server URL.',
        );
      }
      return response.data;
    } catch (error) {
      throw AppException.fromNetwork(error);
    }
  }

  /// Xtream timestamps are expressed as Unix seconds, often as strings.
  /// Some providers use zero to mean that the account does not expire.
  static DateTime? _parseTimestamp(Object? value) {
    final seconds = int.tryParse(optionalText(value) ?? '');
    if (seconds == null || seconds <= 0 || seconds > 253402300799) {
      return null;
    }
    // Keep Unix timestamps in UTC; convert to local time only for display.
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  Future<AccountStatus> authenticate(AccountCredentials credentials) async {
    final result = await _request(credentials);
    if (result is! Map) {
      throw const AppException(
        'The server did not return valid account information.',
      );
    }
    final info = result['user_info'];
    if (info is! Map) {
      throw const AppException('The server did not return user information.');
    }
    final enabled = info['auth'] == true || info['auth'].toString() == '1';
    final status = optionalText(info['status']);
    if (!enabled || (status != null && status.toLowerCase() != 'active')) {
      throw const AppException('Account access is denied or inactive.');
    }
    final expiration = _parseTimestamp(info['exp_date']);
    if (expiration != null && expiration.isBefore(DateTime.now())) {
      throw const AppException('The account has expired.');
    }
    final server = result['server_info'];
    final rawFormats = info['allowed_output_formats'];
    return AccountStatus(
      authorized: true,
      status: status,
      createdAt: _parseTimestamp(info['created_at']),
      expiration: expiration,
      activeConnections: int.tryParse(optionalText(info['active_cons']) ?? ''),
      maxConnections: int.tryParse(optionalText(info['max_connections']) ?? ''),
      isTrial: switch (optionalText(info['is_trial'])) {
        '1' || 'true' => true,
        '0' || 'false' => false,
        _ => null,
      },
      serverTimezone: server is Map ? optionalText(server['timezone']) : null,
      allowedFormats: rawFormats is List
          ? rawFormats
                .map(optionalText)
                .whereType<String>()
                .toList(growable: false)
          : const [],
    );
  }

  Future<List<MediaCategory>> categories(
    AccountCredentials credentials,
    LibraryKind kind, {
    CancelToken? cancelToken,
  }) async {
    final raw = await _request(
      credentials,
      action: kind.categoriesAction,
      cancelToken: cancelToken,
    );
    if (raw is! List) {
      throw const AppException(
        'The provider returned an invalid category list.',
      );
    }
    return raw
        .whereType<Map>()
        .map(
          (value) => MediaCategory.fromJson(Map<String, dynamic>.from(value)),
        )
        .where((category) => category.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<MediaEntry>> catalog(
    AccountCredentials credentials,
    LibraryKind kind, {
    CancelToken? cancelToken,
  }) async {
    final raw = await _request(
      credentials,
      action: kind.listAction,
      cancelToken: cancelToken,
    );
    if (raw is! List) {
      throw const AppException('The provider returned an invalid catalog.');
    }
    final entries = <MediaEntry>[];
    for (final value in raw) {
      if (value is! Map) {
        continue;
      }
      try {
        entries.add(
          MediaEntry.fromJson(Map<String, dynamic>.from(value), kind),
        );
      } on FormatException {
        continue;
      }
    }
    return entries;
  }

  Future<SeriesDetails> seriesDetails(
    AccountCredentials credentials,
    String seriesId,
  ) async {
    final raw = await _request(
      credentials,
      action: 'get_series_info',
      arguments: {'series_id': seriesId},
    );
    if (raw is! Map) {
      throw const AppException(
        'The provider returned invalid series information.',
      );
    }
    return SeriesDetails.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<MediaDetails> movieDetails(
    AccountCredentials credentials,
    String movieId,
  ) async {
    final raw = await _request(
      credentials,
      action: 'get_vod_info',
      arguments: {'vod_id': movieId},
    );
    if (raw is! Map) {
      throw const AppException('The provider returned invalid movie details.');
    }
    return MediaDetails.fromJson(Map<String, dynamic>.from(raw));
  }

  Uri streamUrl(
    AccountCredentials credentials,
    MediaEntry media, {
    String liveFormat = 'm3u8',
  }) {
    final kind = switch (media.kind) {
      LibraryKind.live => 'live',
      LibraryKind.movies => 'movie',
      LibraryKind.series => 'series',
    };
    return ServerAddress.stream(
      ServerAddress.parse(credentials.serverUrl),
      type: kind,
      username: credentials.username,
      password: credentials.password,
      streamId: media.id,
      extension: media.playbackExtension(liveFormat: liveFormat),
    );
  }
}
