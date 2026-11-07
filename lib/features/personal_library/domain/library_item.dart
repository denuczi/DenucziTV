import '../../library/domain/media_models.dart';

/// Do not persist artwork URLs carrying secrets or non-HTTP schemes.
String? safeArtworkUrl(String? value) {
  final uri = Uri.tryParse(value ?? '');
  if (uri == null ||
      !uri.hasAuthority ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.userInfo.isNotEmpty ||
      uri.queryParameters.keys.any(
        (key) => const {
          'username',
          'password',
          'token',
          'auth',
          'key',
          'api_key',
        }.contains(key.toLowerCase()),
      )) {
    return null;
  }
  return value;
}

/// Local library metadata. Never store provider URLs, tokens, or passwords.
class LibraryItem {
  const LibraryItem({
    required this.accountId,
    required this.mediaId,
    required this.kind,
    required this.title,
    this.imageUrl,
    this.seriesId,
    this.seriesTitle,
    this.season,
    this.episode,
    this.containerExtension,
    this.positionMs = 0,
    this.durationMs = 0,
    this.completed = false,
    this.hiddenFromContinue = false,
    this.available = true,
    this.updatedAtMs = 0,
  });

  final String accountId;
  final String mediaId;
  final LibraryKind kind;
  final String title;
  final String? imageUrl;
  final String? seriesId;
  final String? seriesTitle;
  final int? season;
  final int? episode;
  final String? containerExtension;
  final int positionMs;
  final int durationMs;
  final bool completed;
  final bool hiddenFromContinue;
  final bool available;
  final int updatedAtMs;

  bool get isEpisode => kind == LibraryKind.series && seriesId != null;
  double? get progress => durationMs > 0
      ? (positionMs / durationMs).clamp(0.0, 1.0).toDouble()
      : null;

  MediaEntry toMediaEntry() => MediaEntry(
    id: mediaId,
    title: title,
    kind: kind,
    imageUrl: imageUrl,
    seasonNumber: season,
    episodeNumber: episode,
    containerExtension: containerExtension,
    seriesId: seriesId,
  );

  factory LibraryItem.fromMedia({
    required String accountId,
    required MediaEntry media,
    String? seriesTitle,
  }) => LibraryItem(
    accountId: accountId,
    mediaId: media.id,
    kind: media.kind,
    title: media.title,
    imageUrl: safeArtworkUrl(media.imageUrl),
    seriesId: media.seriesId,
    seriesTitle: seriesTitle,
    season: media.seasonNumber,
    episode: media.episodeNumber,
    containerExtension: media.containerExtension,
  );
}
