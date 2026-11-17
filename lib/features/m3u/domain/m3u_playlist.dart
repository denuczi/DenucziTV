import '../../../core/errors/app_exception.dart';
import '../../library/domain/media_models.dart';
import 'm3u_media_classifier.dart';

/// An HTTP source and its per-item headers. Never persist these values in SQLite.
final class M3uStream {
  const M3uStream({required this.uri, required this.headers});

  final Uri uri;
  final Map<String, String> headers;
}

/// An immutable, parsed playlist. Stream URLs remain only in memory.
final class M3uPlaylist {
  M3uPlaylist._(this.entries, this.streams)
    : kinds = Map.unmodifiable({
        for (final entry in entries) entry.id: entry.kind,
      });

  final List<MediaEntry> entries;
  final Map<String, M3uStream> streams;
  final Map<String, LibraryKind> kinds;

  List<MediaEntry> forKind(LibraryKind kind, String sourceScope) => [
    for (final entry in entries)
      if (entry.kind == kind) entry.withSourceScope(sourceScope),
  ];

  List<MediaCategory> categoriesFor(LibraryKind kind) {
    final groups = <String>{};
    for (final entry in entries) {
      if (entry.kind == kind && entry.categoryId != null) {
        groups.add(entry.categoryId!);
      }
    }
    return [for (final name in groups) MediaCategory(id: name, name: name)];
  }

  M3uStream? streamFor(String id) => streams[id];

  bool hasEntry(MediaEntry media) => kinds[media.id] == media.kind;
}

/// Parses IPTV Extended M3U rather than HLS media-segment playlists.
/// Malformed entries are skipped so a single broken channel cannot hide
/// thousands of valid channels. An entirely invalid playlist is rejected.
final class M3uPlaylistParser {
  const M3uPlaylistParser();

  static const maxEntries = 100000;
  static const _classifier = M3uMediaClassifier();
  static const _vodMarker = '#EXT-X-PLAYLIST-TYPE:VOD';
  static const maxLineLength = 16384;
  static final RegExp _attribute = RegExp(
    r'''([a-zA-Z][a-zA-Z0-9_-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s]+))''',
  );
  static final RegExp _controls = RegExp(r'[\x00-\x1f\x7f]');

  M3uPlaylist parse(String text, {Uri? baseUri}) {
    final lines = text.replaceFirst('\uFEFF', '').split(RegExp(r'\r\n|\n|\r'));
    final first = lines.indexWhere((line) => line.trim().isNotEmpty);
    if (first < 0 ||
        !RegExp(r'^#EXTM3U(?:\s|$)').hasMatch(lines[first].trim())) {
      throw const AppException('The file is not an Extended M3U playlist.');
    }
    // HLS uses EXTINF for segments. Accept only the VOD marker as a
    // per-entry IPTV extension; any other HLS directive indicates a manifest.
    // Never import its segments as independent channels or movies.
    if (lines.any((raw) {
      final line = raw.trim();
      return line.toUpperCase().startsWith('#EXT-X-') &&
          line.toUpperCase() != _vodMarker;
    })) {
      throw const AppException(
        'This is an HLS playback manifest, not an IPTV channel list.',
      );
    }

    final entries = <MediaEntry>[];
    final streams = <String, M3uStream>{};
    var liveNumber = 0;
    Map<String, String>? pending;
    String? pendingName;
    var pendingVod = false;
    String? group;
    for (final raw in lines.skip(first + 1)) {
      if (raw.length > maxLineLength) {
        pending = null;
        pendingName = null;
        pendingVod = false;
        continue;
      }
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXTGRP:')) {
        group = _optional(line.substring('#EXTGRP:'.length));
        continue;
      }
      if (line.toUpperCase() == _vodMarker) {
        // This tag belongs to the EXTINF entry awaiting its stream URL.
        // An orphan marker must not affect a later channel.
        if (pending != null) {
          pendingVod = true;
        }
        continue;
      }
      if (line.startsWith('#EXTINF:')) {
        pendingVod = false;
        final metadata = line.substring('#EXTINF:'.length);
        final comma = _unquotedComma(metadata);
        final attributes = comma < 0 ? metadata : metadata.substring(0, comma);
        pending = <String, String>{};
        for (final match in _attribute.allMatches(attributes)) {
          pending[match.group(1)!.toLowerCase()] =
              match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
        }
        pendingName = comma < 0
            ? null
            : _optional(metadata.substring(comma + 1));
        continue;
      }
      if (line.startsWith('#')) continue;
      if (pending == null) continue;
      final attributes = pending;
      pending = null;
      final isVod = pendingVod;
      pendingVod = false;
      final title =
          pendingName ?? _optional(attributes['tvg-name']) ?? 'Untitled';
      pendingName = null;
      try {
        final source = _parseStream(line, baseUri);
        // Include per-stream headers in the identity. A URL can legitimately
        // appear twice with different access headers and must remain distinct.
        final sortedHeaders = source.headers.entries.toList()
          ..sort((left, right) => left.key.compareTo(right.key));
        final id = _stableId(
          [
            source.uri.toString(),
            for (final header in sortedHeaders) '${header.key}:${header.value}',
          ].join('\u0000'),
        );
        if (streams.containsKey(id)) continue;
        final groupName = _optional(attributes['group-title']) ?? group;
        final kind = _classifier.classify(source.uri, isVod: isVod);
        final extension = source.uri.pathSegments.isEmpty
            ? null
            : _optional(
                source.uri.pathSegments.last.split('.').last.toLowerCase(),
              );
        final logo = _safeLogo(attributes['tvg-logo']);
        streams[id] = source;
        if (kind == LibraryKind.live) liveNumber++;
        entries.add(
          MediaEntry(
            id: id,
            title: title,
            kind: kind,
            categoryId: groupName,
            imageUrl: logo,
            containerExtension: extension,
            channelNumber: kind == LibraryKind.live ? liveNumber : null,
          ),
        );
        if (entries.length > maxEntries) {
          throw const AppException('The playlist exceeds the entry limit.');
        }
      } on AppException catch (exception) {
        if (exception.message == 'The playlist exceeds the entry limit.') {
          rethrow;
        }
        // An individual unsafe or malformed item is not playable.
      } on FormatException {
        // Malformed URLs and percent escapes are ignored per item.
      }
    }
    if (entries.isEmpty) {
      throw const AppException('The playlist contains no playable entries.');
    }
    return M3uPlaylist._(List.unmodifiable(entries), Map.unmodifiable(streams));
  }

  int _unquotedComma(String value) {
    String? quote;
    for (var i = 0; i < value.length; i++) {
      final character = value[i];
      if (quote != null) {
        if (character == quote) {
          quote = null;
        }
      } else if (character == '"' || character == "'") {
        quote = character;
      } else if (character == ',') {
        return i;
      }
    }
    return -1;
  }

  M3uStream _parseStream(String input, Uri? baseUri) {
    final segments = input.split('|');
    final address = segments.first.trim();
    if (_controls.hasMatch(address) || address.length > 8192) {
      throw const AppException('Invalid media URL.');
    }
    final candidate = Uri.tryParse(address);
    if (candidate == null) throw const AppException('Invalid media URL.');
    final uri = baseUri?.resolveUri(candidate) ?? candidate;
    if ((uri.scheme != 'http' && uri.scheme != 'https') ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const AppException('Unsupported media URL.');
    }
    final headers = <String, String>{};
    for (final segment in segments.skip(1)) {
      for (final pair in segment.split('&')) {
        final equals = pair.indexOf('=');
        if (equals <= 0) throw const AppException('Invalid pipe header.');
        final key = pair.substring(0, equals).trim().toLowerCase();
        final normalized = switch (key) {
          'user-agent' || 'user_agent' => 'User-Agent',
          'referer' || 'referrer' => 'Referer',
          'origin' => 'Origin',
          _ => throw const AppException('Unsupported pipe header.'),
        };
        if (headers.containsKey(normalized)) {
          throw const AppException('Duplicate pipe header.');
        }
        final value = Uri.decodeQueryComponent(pair.substring(equals + 1));
        if (value.isEmpty || value.length > 2048 || _controls.hasMatch(value)) {
          throw const AppException('Invalid pipe header value.');
        }
        if (normalized != 'User-Agent') {
          final origin = Uri.tryParse(value);
          if (origin == null ||
              (origin.scheme != 'http' && origin.scheme != 'https') ||
              !origin.hasAuthority ||
              origin.host.isEmpty ||
              origin.userInfo.isNotEmpty ||
              origin.hasFragment ||
              (normalized == 'Origin' &&
                  (origin.path.isNotEmpty && origin.path != '/' ||
                      origin.hasQuery))) {
            throw const AppException('Invalid Origin or Referer.');
          }
        }
        headers[normalized] = value;
      }
    }
    return M3uStream(uri: uri, headers: Map.unmodifiable(headers));
  }

  String? _safeLogo(String? logo) {
    final value = _optional(logo);
    if (value == null || value.length > 2048) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.queryParameters.keys.any(
          (key) => {
            'password',
            'username',
            'token',
            'auth',
            'key',
          }.contains(key.toLowerCase()),
        )) {
      return null;
    }
    return value;
  }

  String? _optional(String? text) {
    final value = text?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String _stableId(String source) {
    int hash(String value) {
      var result = 2166136261;
      for (final unit in value.codeUnits) {
        result = ((result ^ unit) * 16777619) & 0xffffffff;
      }
      return result;
    }

    return '${hash(source).toRadixString(16).padLeft(8, '0')}'
        '${hash(source.split('').reversed.join()).toRadixString(16).padLeft(8, '0')}';
  }
}
