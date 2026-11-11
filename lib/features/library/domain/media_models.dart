import '../../../core/errors/app_exception.dart';

enum LibraryKind { live, movies, series }

extension LibraryKindInfo on LibraryKind {
  String get label => switch (this) {
    LibraryKind.live => 'Live TV',
    LibraryKind.movies => 'Movies',
    LibraryKind.series => 'Series',
  };

  String get listAction => switch (this) {
    LibraryKind.live => 'get_live_streams',
    LibraryKind.movies => 'get_vod_streams',
    LibraryKind.series => 'get_series',
  };

  String get categoriesAction => switch (this) {
    LibraryKind.live => 'get_live_categories',
    LibraryKind.movies => 'get_vod_categories',
    LibraryKind.series => 'get_series_categories',
  };
}

String? optionalText(Object? value) {
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty || text == 'null' ? null : text;
}

class MediaCategory {
  const MediaCategory({required this.id, required this.name});

  final String id;
  final String name;

  factory MediaCategory.fromJson(Map<String, dynamic> value) => MediaCategory(
    id: optionalText(value['category_id']) ?? '',
    name: optionalText(value['category_name']) ?? 'Unnamed category',
  );
}

class MediaEntry {
  const MediaEntry({
    required this.id,
    required this.title,
    required this.kind,
    this.categoryId,
    this.imageUrl,
    this.containerExtension,
    this.channelNumber,
    this.rating,
    this.plot,
    this.seasonNumber,
    this.episodeNumber,
    this.seriesId,
    this.sourceScope = '',
  });

  final String id;
  final String title;
  final LibraryKind kind;
  final String? categoryId;
  final String? imageUrl;
  final String? containerExtension;

  /// One-based position in the loaded Live TV catalogue, not a provider ID.
  /// Category filtering and searching must never renumber a channel.
  final int? channelNumber;

  final String? rating;
  final String? plot;
  final int? seasonNumber;
  final int? episodeNumber;

  /// Parent series ID for an episode; never use the episode title as identity.
  final String? seriesId;

  /// An opaque connection generation, never a provider URL or credential.
  final String sourceScope;

  MediaEntry withSourceScope(String scope) => MediaEntry(
    id: id,
    title: title,
    kind: kind,
    categoryId: categoryId,
    imageUrl: imageUrl,
    containerExtension: containerExtension,
    channelNumber: channelNumber,
    rating: rating,
    plot: plot,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
    seriesId: seriesId,
    sourceScope: scope,
  );

  MediaEntry withSeries(String parentId) => MediaEntry(
    id: id,
    title: title,
    kind: kind,
    categoryId: categoryId,
    imageUrl: imageUrl,
    containerExtension: containerExtension,
    channelNumber: channelNumber,
    rating: rating,
    plot: plot,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
    seriesId: parentId,
    sourceScope: sourceScope,
  );

  factory MediaEntry.fromJson(
    Map<String, dynamic> json,
    LibraryKind kind, {
    int? channelNumber,
  }) {
    final id = optionalText(
      json[kind == LibraryKind.series ? 'series_id' : 'stream_id'],
    );
    if (id == null) {
      throw const FormatException('Entry ID is missing');
    }
    return MediaEntry(
      id: id,
      title: optionalText(json['name']) ?? 'Untitled',
      kind: kind,
      categoryId: optionalText(json['category_id']),
      imageUrl:
          optionalText(
            json[kind == LibraryKind.live ? 'stream_icon' : 'cover'],
          ) ??
          optionalText(json['stream_icon']),
      containerExtension: optionalText(json['container_extension']),
      channelNumber: kind == LibraryKind.live && (channelNumber ?? 0) > 0
          ? channelNumber
          : null,
      rating: optionalText(json['rating']),
      plot: optionalText(json['plot']),
    );
  }

  factory MediaEntry.episode(Map<String, dynamic> json, int season) {
    final id = optionalText(json['id']);
    if (id == null) {
      throw const FormatException('Episode ID is missing');
    }
    final info = json['info'] is Map ? json['info'] as Map : const {};
    return MediaEntry(
      id: id,
      title: optionalText(json['title']) ?? 'Episode $id',
      kind: LibraryKind.series,
      seasonNumber: season,
      episodeNumber: int.tryParse(optionalText(json['episode_num']) ?? ''),
      containerExtension:
          optionalText(json['container_extension']) ??
          optionalText(info['container_extension']),
      // Xtream-compatible providers may expose episode artwork in either
      // the nested info object or the top-level episode record.
      imageUrl:
          optionalText(info['movie_image']) ??
          optionalText(info['cover_big']) ??
          optionalText(info['cover']) ??
          optionalText(json['movie_image']) ??
          optionalText(json['cover']) ??
          optionalText(json['stream_icon']),
      plot: optionalText(info['plot']) ?? optionalText(json['plot']),
    );
  }

  /// Returns only supported extensions; unknown formats must be checked before playback.
  String playbackExtension({String liveFormat = 'm3u8'}) {
    if (kind == LibraryKind.live) {
      return liveFormat;
    }
    final requested = (containerExtension ?? 'mp4').toLowerCase();
    if (!RegExp(r'^[a-z0-9]{2,6}$').hasMatch(requested)) {
      throw const AppException(
        'The provider returned an unsupported file extension.',
      );
    }
    return requested;
  }
}

/// Optional metadata returned by providers; absent fields are never fabricated.
class MediaDetails {
  const MediaDetails({
    this.plot,
    this.genre,
    this.releaseDate,
    this.duration,
    this.director,
    this.cast,
    this.rating,
    this.country,
    this.imageUrl,
  });

  final String? plot;
  final String? genre;
  final String? releaseDate;
  final String? duration;
  final String? director;
  final String? cast;
  final String? rating;
  final String? country;
  final String? imageUrl;

  factory MediaDetails.fromJson(Map<String, dynamic> json) {
    final rawInfo = json['info'];
    final info = rawInfo is Map ? rawInfo : json;
    final rawMovie = json['movie_data'];
    final movie = rawMovie is Map ? rawMovie : const <String, Object?>{};
    String? field(String key, [String? alternate]) =>
        optionalText(info[key]) ??
        (alternate == null ? null : optionalText(info[alternate])) ??
        optionalText(movie[key]);

    return MediaDetails(
      plot: field('plot', 'description'),
      genre: field('genre'),
      releaseDate: field('releasedate', 'release_date'),
      duration: field('duration'),
      director: field('director'),
      cast: field('cast', 'actors'),
      rating: field('rating'),
      country: field('country'),
      imageUrl:
          field('movie_image', 'cover_big') ??
          field('cover') ??
          field('stream_icon'),
    );
  }
}

class SeriesDetails {
  const SeriesDetails({
    required this.episodesBySeason,
    this.metadata = const MediaDetails(),
  });

  final Map<int, List<MediaEntry>> episodesBySeason;
  final MediaDetails metadata;

  /// Counts only seasons and episodes returned by the selected provider.
  int get seasonCount => episodesBySeason.length;
  int get episodeCount => episodesBySeason.values.fold<int>(
    0,
    (total, episodes) => total + episodes.length,
  );
  int episodeCountForSeason(int season) =>
      episodesBySeason[season]?.length ?? 0;

  /// Episodes in playback order, including season transitions.
  List<MediaEntry> get playbackQueue {
    final orderedSeasons = episodesBySeason.keys.toList()..sort();
    return List.unmodifiable([
      for (final season in orderedSeasons) ...episodesBySeason[season]!,
    ]);
  }

  factory SeriesDetails.fromJson(Map<String, dynamic> json) {
    final raw = json['episodes'];
    if (raw is! Map) {
      return SeriesDetails(
        episodesBySeason: const {},
        metadata: MediaDetails.fromJson(json),
      );
    }
    final mapped = <int, List<MediaEntry>>{};
    for (final item in raw.entries) {
      final season = int.tryParse(item.key.toString());
      if (season == null || item.value is! List) {
        continue;
      }
      final episodes = <MediaEntry>[];
      for (final episode in item.value as List) {
        if (episode is! Map) {
          continue;
        }
        try {
          episodes.add(
            MediaEntry.episode(Map<String, dynamic>.from(episode), season),
          );
        } on FormatException {
          continue;
        }
      }
      // Providers do not consistently return episodes in playback order.
      // Keep original relative order when episode numbers are missing or equal.
      final ordered = episodes.indexed.toList()
        ..sort((a, b) {
          final left = a.$2.episodeNumber;
          final right = b.$2.episodeNumber;
          if (left == null && right == null) {
            return a.$1.compareTo(b.$1);
          }
          if (left == null) {
            return 1;
          }
          if (right == null) {
            return -1;
          }
          final result = left.compareTo(right);
          return result == 0 ? a.$1.compareTo(b.$1) : result;
        });
      mapped[season] = ordered
          .map((record) => record.$2)
          .toList(growable: false);
    }
    return SeriesDetails(
      episodesBySeason: mapped,
      metadata: MediaDetails.fromJson(json),
    );
  }
}
