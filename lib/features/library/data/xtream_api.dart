import 'dart:async';

import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/models/account.dart';
import '../../../core/network/http_redirect_policy.dart';
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
    if (credentials.protected &&
        (credentials.linkExpired || credentials.accessGrant == null)) {
      throw const AppException('The protected link has expired.');
    }
    if (credentials.protected &&
        credentials.accessGrant?.allowsNewSessions != true) {
      throw const AppException(
        'This content is unavailable in the current account source.',
      );
    }
    final base = ServerAddress.parse(credentials.serverUrl);
    final url = ServerAddress.api(base, {
      'username': credentials.username,
      'password': credentials.password,
      'action': ?action,
      ...arguments,
    });
    final requestCancellation =
        cancelToken ?? (credentials.protected ? CancelToken() : null);
    final accessRevocation = credentials.accessGrant?.revocations.listen(
      (_) => requestCancellation?.cancel(),
    );
    final policy = HttpRedirectPolicy(
      allowHttpsToHttpRedirect: _network.allowHttpsToHttpRedirects,
    );
    final visited = <Uri>{};
    var current = url;
    var redirects = 0;
    try {
      while (true) {
        if (!visited.add(current)) {
          throw const AppException(
            'The provider returned an API redirect loop.',
          );
        }
        final response = await _network.dio.getUri<Object?>(
          current,
          cancelToken: requestCancellation,
          options: Options(
            responseType: ResponseType.json,
            followRedirects: false,
          ),
        );
        final status = response.statusCode ?? 500;
        if (HttpRedirectPolicy.redirectCodes.contains(status)) {
          if (redirects >= HttpRedirectPolicy.maxRedirects) {
            throw const AppException(
              'The provider exceeded the API redirect limit.',
            );
          }
          final location = response.headers.value('location');
          if (location == null) {
            throw const AppException(
              'The provider redirected without a Location header.',
            );
          }
          final next = policy.resolve(current, location);
          // Interceptors or custom transports may add authentication headers.
          // Reject cross-origin redirects rather than forwarding such secrets.
          if (next.origin != current.origin &&
              response.requestOptions.headers.keys.any(
                (name) => const {
                  'authorization',
                  'proxy-authorization',
                  'cookie',
                }.contains(name.toLowerCase()),
              )) {
            throw const AppException(
              'Authenticated headers cannot cross provider API origins.',
            );
          }
          current = next;
          redirects++;
          continue;
        }
        if (status >= 300) {
          throw const AppException(
            'The provider returned an unexpected API redirect.',
          );
        }
        if (credentials.protected &&
            (credentials.linkExpired ||
                credentials.accessGrant?.allowsNewSessions != true)) {
          throw const AppException('The protected link has expired.');
        }
        return response.data;
      }
    } catch (error) {
      throw AppException.fromNetwork(error);
    } finally {
      await accessRevocation?.cancel();
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
    final categories = raw
        .whereType<Map>()
        .map(
          (value) => MediaCategory.fromJson(Map<String, dynamic>.from(value)),
        )
        .where((category) => category.id.isNotEmpty)
        .toList(growable: false);
    if (credentials.protected && categories.length != raw.length) {
      throw const AppException(
        'The provider returned an invalid category list.',
      );
    }
    return categories;
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
        if (credentials.protected) {
          throw const AppException('The provider returned an invalid catalog.');
        }
        continue;
      }
      try {
        entries.add(
          MediaEntry.fromJson(Map<String, dynamic>.from(value), kind),
        );
      } on FormatException {
        if (credentials.protected) {
          throw const AppException('The provider returned an invalid catalog.');
        }
        continue;
      }
    }
    return credentials.sourceScope.isEmpty
        ? entries
        : entries
              .map((entry) => entry.withSourceScope(credentials.sourceScope))
              .toList(growable: false);
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
    final details = SeriesDetails.fromJson(Map<String, dynamic>.from(raw));
    if (credentials.sourceScope.isEmpty) return details;
    return SeriesDetails(
      metadata: details.metadata,
      episodesBySeason: {
        for (final entry in details.episodesBySeason.entries)
          entry.key: entry.value
              .map(
                (episode) => episode.withSourceScope(credentials.sourceScope),
              )
              .toList(growable: false),
      },
    );
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
    if (credentials.protected &&
        (credentials.linkExpired || credentials.accessGrant == null)) {
      throw const AppException('The protected link has expired.');
    }
    if (credentials.protected &&
        credentials.accessGrant?.allowsNewSessions != true) {
      throw const AppException(
        'This content is unavailable in the current account source.',
      );
    }
    if (credentials.sourceScope != media.sourceScope) {
      throw const AppException(
        'This content is unavailable in the current account source.',
      );
    }
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

  Uri shareableStreamUrl(AccountCredentials credentials, MediaEntry media) {
    if (credentials.protected) {
      throw const AppException(
        'Protected accounts do not allow sharing links or playlists.',
      );
    }
    return streamUrl(credentials, media);
  }
}
