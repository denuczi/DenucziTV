# Changelog

Changes are grouped by application version. Binary availability is listed on
[GitHub Releases](https://github.com/denuczi/DenucziTV/releases).

## Unreleased

No additional changes recorded.

## [0.6.2](https://github.com/denuczi/DenucziTV/releases/tag/v0.6.2)

### Added

- Stable-only GitHub update discovery with semantic version comparison and a
  separate public HTTP client, without transmitting IPTV account data.
- Non-blocking startup checks with a persisted 24-hour interval and at most one
  unsolicited modal per session, suppressed after user/critical-flow interaction.
- Seven-day version-specific postponement through Maybe later or dismissal;
  manual checks remain available above the existing Settings credits.
- English/Spanish update dialog with bounded plain-text notes and official,
  platform-compatible assisted downloads for Debian/Ubuntu x64 and Windows x64.
  Missing packages offer release details without substituting other artifacts.
- Mocked update regression tests and an isolated desktop modal preview.

Automatic installer execution and application restarts are not part of 0.6.2.
See [the update guide](docs/UPDATES.md) for version semantics, installer naming,
postponement, privacy, verification, and the absence of unattended installation.

## [0.6.1](https://github.com/denuczi/DenucziTV/releases/tag/v0.6.1) — Pre-release

### Fixed

- Load protected-account catalogs by section. Connecting loads Live TV; Movies
  and Series are requested when opened instead of delaying entry while every
  catalog downloads. Visited sections reuse the normal connection cache.
- Validate the visible section during credential renewal before activating the
  new connection. Failed validation retains the previous valid connection;
  effective link expiry still revokes access.
- Clear caches from the previous source on successful renewal. Navigation during
  renewal loads the selected section using the new credentials without mixing
  content IDs or history between catalog generations.
- Make the test API preserve catalog generations, matching the production API,
  and add regressions for section loading, renewal, cache reuse, and source scope.

### Package validation

- Linux release build completed for `0.6.1+1`.
- Generated `denuczitv_0.6.1+1-1_amd64.deb`; all 13 packaging integration checks
  passed on the maintainer's machine.
- Lintian was not installed during that run. Native dependency, ELF, desktop
  integration, permissions, payload checksum, and JNI-policy checks passed.

## 0.6.0

### Added

- Protected Single Link as an additional connection method using a permanent
  HTTP or HTTPS link to resolve Xtream credentials without importing M3U.
- Secure storage of the original link and resolved connection, persistent random
  installation identification, and an identifying User-Agent sent only to the
  initial permanent-link request. Provider, artwork, playback, and download
  traffic retains the normal or user-configured User-Agent.
- Automatic credential checks every 24 hours, manual updates, bounded recovery,
  and effective `dtv_expires` revocation of playback and downloads while retaining
  the account, history, favorites, progress, and downloaded data.
- Catalog generations and SQLite version 2 migration to preserve existing
  records and prevent reused provider IDs from inheriting unrelated progress.

### Fixed

- Restrict M3U export and URL copying only for protected accounts, preserving
  manual Xtream functionality. Settings explains unavailable protected-account
  actions and retains manual-account preferences; downloads remain available.
- Use informational colors for download-start notifications and active transfers.
  Keep error and completion indicators visually distinct.
- Localize download states, automatic reconnection, and common connection errors
  in English and Spanish, including retry guidance and partial-data preservation.
- Remove the reconnection notice when a validated transfer resumes.
- Correct widget-test controller ownership and expiry-test clock setup to avoid
  pending timers and stalled asynchronous queues.

## 0.5.3

### Added

- Initial public source baseline with Xtream-compatible accounts, live TV,
  movies, series, and native desktop playback for Linux and Windows.
- Downloads with retry and HTTP Range resume when supported by the provider.
- Account-scoped favorites, watch history, and playback progress stored in SQLite.
- English and Spanish localization, MIT license, contributor documentation,
  issue templates, and desktop CI workflow.
- Debian packaging with native dependency detection, desktop integration,
  checksums, integration checks, and CI artifacts.
- Installation-first README with pre-release downloads, screenshots, and a
  separate development guide.

### Fixed

- Keep the M3U export confirmation compact and scrollable on smaller windows.
- Clarify that account creation and expiration dates come from the provider and
  are displayed in the user's local time zone.
- Prevent the transitive Android JNI plugin from adding an unused JVM dependency
  to Linux builds on hosts with a JDK, including GitHub Actions runners.

No verified release history is available before the 0.5.3 source baseline.
