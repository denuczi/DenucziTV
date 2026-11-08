import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../domain/stable_release.dart';
import '../domain/semantic_version.dart';

class UpdateRequestFailure implements Exception {
  const UpdateRequestFailure(this.status);
  final UpdateStatus status;
}

/// Independent, unauthenticated transport. Never reuse the IPTV NetworkClient.
class GitHubReleaseApi {
  GitHubReleaseApi({Dio? client}) : _client = client ?? Dio() {
    _client.options = BaseOptions(
      baseUrl:
          'https://api.github.com/repos/${StableRelease.owner}/${StableRelease.repository}',
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 8),
      followRedirects: false,
      validateStatus: (status) => status != null,
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'DenucziTV-UpdateChecker/1',
        'X-GitHub-Api-Version': '2026-03-10',
      },
    );
  }

  final Dio _client;
  static const maxPageBytes = 4 * 1024 * 1024;
  static const maxPages = 10;

  Future<List<StableRelease>> fetch(CancelToken cancellation) =>
      _guard(() => _fetchPages(cancellation), cancellation);

  /// Refresh stability and asset metadata immediately before assisted download.
  Future<StableRelease?> verifyRelease(String tag, CancelToken cancellation) {
    final version = SemanticVersion.tryParse(tag);
    if (version == null || !version.isStable) return Future.value(null);
    return _guard(() async {
      final raw = await _readJson(
        '/releases/tags/${Uri.encodeComponent(tag)}',
        cancellation,
      );
      final release = StableRelease.parse(raw);
      if (release != null && release.tag != tag) {
        throw const FormatException('Unexpected release tag');
      }
      return release;
    }, cancellation);
  }

  Future<T> _guard<T>(
    Future<T> Function() request,
    CancelToken cancellation,
  ) async {
    try {
      return await request().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          cancellation.cancel();
          throw const UpdateRequestFailure(UpdateStatus.timedOut);
        },
      );
    } on UpdateRequestFailure {
      rethrow;
    } on FormatException {
      throw const UpdateRequestFailure(UpdateStatus.invalidResponse);
    } on TimeoutException {
      throw const UpdateRequestFailure(UpdateStatus.timedOut);
    } on DioException catch (error) {
      throw UpdateRequestFailure(switch (error.type) {
        DioExceptionType.cancel => UpdateStatus.cancelled,
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout => UpdateStatus.timedOut,
        DioExceptionType.connectionError => UpdateStatus.offline,
        _ =>
          error.error is SocketException
              ? UpdateStatus.offline
              : UpdateStatus.serverError,
      });
    } catch (_) {
      throw const UpdateRequestFailure(UpdateStatus.serverError);
    }
  }

  Future<List<StableRelease>> _fetchPages(CancelToken cancellation) async {
    final releases = <StableRelease>[];
    for (var page = 1; page <= maxPages; page++) {
      final data = await _readJson(
        '/releases',
        cancellation,
        queryParameters: {'per_page': 100, 'page': page},
      );
      if (data is! List || data.length > 100) {
        throw const FormatException('Invalid release list');
      }
      for (final item in data) {
        final release = StableRelease.parse(item);
        if (release != null) releases.add(release);
      }
      if (data.length < 100) return releases;
    }
    // Never claim an answer based on an incomplete, truncated release history.
    throw const UpdateRequestFailure(UpdateStatus.invalidResponse);
  }

  Future<Object?> _readJson(
    String path,
    CancelToken cancellation, {
    Map<String, Object> queryParameters = const {},
  }) async {
    final response = await _client.get<ResponseBody>(
      path,
      queryParameters: queryParameters,
      cancelToken: cancellation,
      options: Options(responseType: ResponseType.stream),
    );
    final body = response.data;
    if (body == null) throw const FormatException('Missing response');
    final status = response.statusCode;
    if (status != 200) {
      await body.stream.listen(null).cancel();
      throw UpdateRequestFailure(
        status == 403 || status == 429
            ? UpdateStatus.rateLimited
            : UpdateStatus.serverError,
      );
    }
    final length = int.tryParse(response.headers.value('content-length') ?? '');
    if (length != null && length > maxPageBytes) {
      await body.stream.listen(null).cancel();
      throw const FormatException('Oversized release response');
    }
    final bytes = BytesBuilder(copy: false);
    var byteCount = 0;
    await for (final chunk in body.stream) {
      if (cancellation.isCancelled) {
        throw const UpdateRequestFailure(UpdateStatus.cancelled);
      }
      if (byteCount + chunk.length > maxPageBytes) {
        throw const FormatException('Oversized release response');
      }
      byteCount += chunk.length;
      bytes.add(chunk);
    }
    return jsonDecode(utf8.decode(bytes.takeBytes()));
  }

  void dispose() => _client.close(force: true);
}
