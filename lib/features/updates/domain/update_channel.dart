/// Distribution channel that owns application updates.
enum UpdateChannel {
  /// Existing Windows EXE and Debian builds use signed GitHub releases.
  githubReleases,

  /// Microsoft Store builds must never contact the GitHub release API.
  microsoftStore,
}

/// Resolves the update channel from the compile-time Store flag.
///
/// The Microsoft Store workflow passes `--dart-define=DENUCZI_STORE_BUILD=true`.
/// Every other build keeps the existing GitHub updater unchanged.
UpdateChannel updateChannelFor({required bool storeBuild}) =>
    storeBuild ? UpdateChannel.microsoftStore : UpdateChannel.githubReleases;

abstract final class AppDistribution {
  /// Set only by the Microsoft Store packaging workflow.
  static const bool storeBuild = bool.fromEnvironment('DENUCZI_STORE_BUILD');

  static UpdateChannel get updateChannel =>
      updateChannelFor(storeBuild: storeBuild);

  /// Whether the GitHub release updater may be created for this build.
  static bool get usesGitHubUpdater =>
      updateChannel == UpdateChannel.githubReleases;
}
