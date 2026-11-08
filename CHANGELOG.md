# Changelog

User-visible changes are recorded here. Development snapshots are not releases.

## Unreleased

### Fixed

- Keep the M3U export confirmation compact and scrollable on smaller windows.
- Clarify that account creation and expiration dates come from the provider and
  are displayed in the user's local time zone.

- Prevent Android's transitive JNI plugin from adding an unused JVM dependency
  to Linux builds on hosts with a JDK, including GitHub Actions runners.

### Added

- Installation-first README with pre-release downloads, screenshots, and a
  separate development guide.

- Debian packaging with native dependency detection, desktop integration,
  checksums, integration checks, and CI artifacts.

- Initial public source baseline for the 0.5.3 development candidate.
- Xtream-compatible accounts, live TV, movies, series, and native desktop playback.
- Downloads with retry and HTTP Range resume when supported by the provider.
- Account-scoped favorites, watch history, and playback progress stored in SQLite.
- English and Spanish application localization.
- MIT license, contributor documentation, issue templates, and desktop CI workflow.

No verified release history is available before this baseline.
