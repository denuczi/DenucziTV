import '../../library/domain/media_models.dart';

/// Classifies M3U entries from their media source, not from category labels.
/// Groups describe how a provider organizes content and are not proof of VOD.
final class M3uMediaClassifier {
  const M3uMediaClassifier();

  /// An explicit per-entry VOD marker takes precedence over the URL format.
  /// Otherwise only direct video-file extensions identify a movie.
  /// HLS manifests and transport streams remain Live TV unless marked VOD.
  LibraryKind classify(Uri uri, {bool isVod = false}) {
    if (isVod) {
      return LibraryKind.movies;
    }
    final path = uri.path.toLowerCase();
    if (path.endsWith('.mp4') ||
        path.endsWith('.mkv') ||
        path.endsWith('.avi')) {
      return LibraryKind.movies;
    }
    return LibraryKind.live;
  }
}
