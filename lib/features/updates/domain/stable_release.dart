import 'semantic_version.dart';

enum UpdateTarget { debianX64, windowsX64, unsupported }

enum UpdateStatus {
  idle,
  checking,
  updateAvailable,
  upToDate,
  noStableRelease,
  packageUnavailable,
  offline,
  timedOut,
  rateLimited,
  serverError,
  invalidResponse,
  metadataUnavailable,
  cancelled,
}

class UpdateCheckResult {
  const UpdateCheckResult(this.status, [this.release]);
  final UpdateStatus status;
  final StableRelease? release;
  bool get offersUpdate =>
      status == UpdateStatus.updateAvailable ||
      status == UpdateStatus.packageUnavailable;
}

class ReleaseAsset {
  const ReleaseAsset._(this.name, this.url);
  final String name;
  final Uri url;
}

/// Constructible only through strict parsing of a stable, published release.
class StableRelease {
  StableRelease._(
    this.tag,
    this.version,
    this.url,
    this.notes,
    this.notesTruncated,
    this.assets,
  );
  final String tag;
  final SemanticVersion version;
  final Uri url;
  final String notes;

  /// True when an unusually long body is shortened for UI responsiveness.
  /// The complete notes remain available at the verified GitHub release URL.
  final bool notesTruncated;

  static const maxReleaseNotesCharacters = 16000;
  final List<ReleaseAsset> assets;

  static const owner = 'denuczi';
  static const repository = 'DenucziTV';

  static bool officialUrl(Uri uri, List<String> tail) =>
      uri.scheme == 'https' &&
      uri.host == 'github.com' &&
      (!uri.hasPort || uri.port == 443) &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      _same(uri.pathSegments, [owner, repository, 'releases', ...tail]);

  static bool _same(List<String> left, List<String> right) =>
      left.length == right.length &&
      List.generate(
        left.length,
        (i) => left[i] == right[i],
      ).every((value) => value);

  /// Invalid version tags are ineligible. Malformed stable metadata is an error,
  /// rather than evidence that the installed app is up to date.
  static StableRelease? parse(Object? raw) {
    if (raw is! Map || raw['draft'] is! bool || raw['prerelease'] is! bool) {
      throw const FormatException('Invalid release flags');
    }
    if (raw['draft'] == true || raw['prerelease'] == true) return null;
    final tag = raw['tag_name'];
    if (tag is! String) throw const FormatException('Missing release tag');
    final version = SemanticVersion.tryParse(tag);
    if (version == null || !version.isStable) return null;
    final link = raw['html_url'];
    final published = raw['published_at'];
    final assets = raw['assets'];
    final notes = raw['body'];
    if (link is! String ||
        published is! String ||
        DateTime.tryParse(published) == null ||
        assets is! List ||
        (notes != null && notes is! String)) {
      throw const FormatException('Invalid published release');
    }
    final url = Uri.tryParse(link);
    if (url == null || !officialUrl(url, ['tag', tag])) {
      throw const FormatException('Invalid release provenance');
    }
    final accepted = <ReleaseAsset>[];
    for (final asset in assets) {
      if (asset is! Map ||
          asset['state'] != 'uploaded' ||
          asset['name'] is! String ||
          asset['browser_download_url'] is! String ||
          asset['size'] is! int ||
          (asset['size'] as int) <= 0) {
        continue;
      }
      final name = asset['name'] as String;
      if (name.length > 200) continue;
      final assetUrl = Uri.tryParse(asset['browser_download_url'] as String);
      if (assetUrl != null && officialUrl(assetUrl, ['download', tag, name])) {
        accepted.add(ReleaseAsset._(name, assetUrl));
      }
    }
    final normalizedNotes = (notes as String? ?? '').replaceAll(
      RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f\u202a-\u202e\u2066-\u2069]'),
      '',
    );
    // Keep enough room for real release announcements without giving a single
    // oversized API field unlimited rendering work on the UI thread.
    final codePoints = normalizedNotes.runes
        .take(maxReleaseNotesCharacters + 1)
        .toList(growable: false);
    final shortened = codePoints.length > maxReleaseNotesCharacters;
    var displayedNotes = String.fromCharCodes(
      shortened ? codePoints.take(maxReleaseNotesCharacters) : codePoints,
    );
    if (shortened) {
      // Prefer stopping after a complete paragraph rather than cutting a
      // Markdown link or the last word in half.
      final paragraphEnd = displayedNotes.lastIndexOf('\n\n');
      if (paragraphEnd >= maxReleaseNotesCharacters ~/ 2) {
        displayedNotes = displayedNotes.substring(0, paragraphEnd);
      } else {
        final lineEnd = displayedNotes.lastIndexOf('\n');
        if (lineEnd >= maxReleaseNotesCharacters ~/ 2) {
          displayedNotes = displayedNotes.substring(0, lineEnd);
        }
      }
    }
    return StableRelease._(
      tag,
      version,
      url,
      displayedNotes.trim(),
      shortened,
      List.unmodifiable(accepted),
    );
  }

  ReleaseAsset? assetFor(UpdateTarget target) {
    final pattern = switch (target) {
      UpdateTarget.debianX64 => RegExp(
        r'^denuczitv_([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?-([1-9][0-9]*)_amd64\.deb$',
      ),
      // A documented installer contract, never the bare Flutter application exe.
      UpdateTarget.windowsX64 => RegExp(
        r'^DenucziTV-Setup-([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?-x64\.exe$',
      ),
      UpdateTarget.unsupported => null,
    };
    if (pattern == null) return null;
    final matches = assets.where((asset) {
      final match = pattern.firstMatch(asset.name);
      final candidate = match == null
          ? null
          : SemanticVersion.tryParse(match.group(1)!);
      return candidate != null &&
          candidate.compareTo(version) == 0 &&
          officialUrl(asset.url, ['download', tag, asset.name]);
    }).toList();
    // Prefer the highest package build/revision within the same SemVer version.
    matches.sort((left, right) {
      final l = pattern.firstMatch(left.name)!;
      final r = pattern.firstMatch(right.name)!;
      for (var i = 2; i <= l.groupCount; i++) {
        final order = BigInt.parse(r.group(i) ?? '0')
            .compareTo(BigInt.parse(l.group(i) ?? '0'));
        if (order != 0) return order;
      }
      return left.name.compareTo(right.name);
    });
    return matches.firstOrNull;
  }
}
