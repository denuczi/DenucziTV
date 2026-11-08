# Changelog

User-visible changes are recorded here. Development snapshots are not releases.

## Unreleased

### Fixed

- Use informational colours for download-start notifications and active transfers.
- Localise download states, automatic recovery, and connection failures, with
  retry guidance and retained partial-data information.

- Explain protected-account sharing restrictions in Media actions and disable
  unavailable switches while preserving preferences for manual Xtream accounts.

- Keep the M3U export confirmation compact and scrollable on smaller windows.
- Clarify that account creation and expiration dates come from the provider and
  are displayed in the user's local time zone.

- Prevent Android's transitive JNI plugin from adding an unused JVM dependency
  to Linux builds on hosts with a JDK, including GitHub Actions runners.

### Added

- Protected Single Link accounts with isolated installation identification, secure
  credential renewal, effective link expiry, and scoped catalogue generations.
- SQLite version 2 migration preserving existing manual favourites and progress.
- Account-specific sharing restrictions and regression coverage for protected
  connections without changing manual Xtream export and URL copying.

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
