import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/network_client.dart';
import '../domain/m3u_playlist.dart';

/// Loads only the user-selected playlist document, never playlist media URLs.
/// Redirects are followed explicitly so their count and scheme are validated.
final class M3uSourceRepository {
  M3uSourceRepository(this._network, {M3uPlaylistParser? parser})
    : _parser = parser ?? const M3uPlaylistParser();

  static const maxBytes = 16 * 1024 * 1024;
  static const maxRedirects = 4;
  static final _controls = RegExp(r'[\x00-\x1f\x7f]');

  final NetworkClient _network;
  final M3uPlaylistParser _parser;

  Future<M3uPlaylist> import(String source, {CancelToken? cancelToken}) async {
    final value = source.trim();
    if (value.isEmpty) throw const AppException('Select an M3U playlist.');
    final uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return _loadRemote(uri, cancelToken: cancelToken);
    }
    if (uri != null &&
        uri.hasScheme &&
        !RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value)) {
      throw const AppException('Only HTTP(S) playlist URLs are supported.');
    }
    return _loadLocal(value);
  }

  Future<M3uPlaylist> _loadLocal(String path) async {
    final file = File(path);
    try {
      if (!await file.exists() || await file.length() > maxBytes) {
        throw const AppException('The playlist file is missing or too large.');
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > maxBytes) {
        throw const AppException('The playlist is too large.');
      }
      return await _parse(utf8.decode(bytes));
    } on FileSystemException {
      throw const AppException('The selected playlist file could not be read.');
    } on FormatException {
      throw const AppException('The playlist must be UTF-8 encoded.');
    }
  }

  Future<M3uPlaylist> _loadRemote(Uri uri, {CancelToken? cancelToken}) async {
    var current = _validateUri(uri);
    for (var redirects = 0; redirects <= maxRedirects; redirects++) {
      if (cancelToken?.isCancelled == true) {
        throw const AppException('Playlist import was cancelled.');
      }
      final Response<ResponseBody> response;
      try {
        response = await _network.dio.get<ResponseBody>(
          current.toString(),
          options: Options(
            responseType: ResponseType.stream,
            followRedirects: false,
            validateStatus: (status) => status != null && status < 400,
          ),
          cancelToken: cancelToken,
        );
      } on DioException {
        throw const AppException(
          'The remote playlist could not be downloaded.',
        );
      }
      final status = response.statusCode ?? 0;
      if (const {301, 302, 303, 307, 308}.contains(status)) {
        // Never download a redirect body. Only its Location is meaningful.
        await response.data?.stream.listen((_) {}).cancel();
        if (redirects >= maxRedirects) {
          throw const AppException('The playlist exceeded four redirects.');
        }
        final location = response.headers.value('location');
        if (location == null ||
            location.isEmpty ||
            location.length > 8192 ||
            _controls.hasMatch(location)) {
          throw const AppException(
            'The playlist returned an invalid redirect.',
          );
        }
        final next = _validateUri(current.resolve(location));
        if (current.scheme == 'https' && next.scheme == 'http') {
          throw const AppException(
            'HTTPS-to-HTTP playlist redirects are blocked.',
          );
        }
        current = next;
        continue;
      }
      if (status < 200 || status >= 300 || response.data == null) {
        throw const AppException(
          'The playlist server returned an invalid response.',
        );
      }
      final length = int.tryParse(
        response.headers.value('content-length') ?? '',
      );
      if (length != null && length > maxBytes) {
        throw const AppException('The remote playlist is too large.');
      }
      final collector = BytesBuilder(copy: false);
      var received = 0;
      try {
        await for (final chunk in response.data!.stream) {
          if (cancelToken?.isCancelled == true) {
            throw const AppException('Playlist import was cancelled.');
          }
          received += chunk.length;
          if (received > maxBytes) {
            throw const AppException('The remote playlist is too large.');
          }
          collector.add(chunk);
        }
      } on DioException {
        throw const AppException('The remote playlist transfer failed.');
      }
      try {
        return await _parse(
          utf8.decode(collector.takeBytes()),
          baseUri: current,
        );
      } on FormatException {
        throw const AppException('The remote playlist must be UTF-8 encoded.');
      }
    }
    throw const AppException('The playlist exceeded four redirects.');
  }

  /// Large catalogs can take noticeable time to parse. Keep that work off
  /// the UI isolate, without moving file or network handles across isolates.
  Future<M3uPlaylist> _parse(String text, {Uri? baseUri}) {
    if (text.length < 256 * 1024) {
      return Future<M3uPlaylist>.value(_parser.parse(text, baseUri: baseUri));
    }
    final parser = _parser;
    return Isolate.run(() => parser.parse(text, baseUri: baseUri));
  }

  Uri _validateUri(Uri uri) {
    if ((uri.scheme != 'http' && uri.scheme != 'https') ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.toString().length > 8192) {
      throw const AppException('Invalid playlist URL.');
    }
    return uri;
  }
}
