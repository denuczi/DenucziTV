# Changelog

Changes are grouped by application version. Binary availability is listed on
[GitHub Releases](https://github.com/denuczi/DenucziTV/releases).

## Unreleased

No additional changes recorded.

## [0.6.4](https://github.com/denuczi/DenucziTV/releases/tag/v0.6.4) — Stable

### Added

- Change Live TV channels inside the existing player with `0`–`9` (including
  the numeric keypad), confirmed five seconds after the final digit or
  immediately with `Enter`. `Backspace` edits the number and `Escape` cancels it.
- Navigate the complete Live TV channel list with `Up`/`Down` or `W`/`S`,
  independently of current search results and category filters. Show a brief,
  accessible on-video indicator with the channel number, title and logo after
  keyboard navigation; missing logos use a legible fallback.
- Keep Live TV numbering stable throughout catalog search and filtering.
- Support account-scoped Live TV favorites alongside movie and series favorites,
  with type filters, local search, direct channel playback and confirmed bulk
  deletion that preserves watch history and downloads.
- Persist bounded artwork thumbnails for the personal library, reducing repeat
  requests and keeping available cached covers visible without loading a catalog.

### Changed

- Open My Library at startup and defer Live TV catalog loading until the user
  enters that section. Saved favorites can request the catalog on demand when
  playback requires it.
- Render GitHub release notes as Markdown in an accessible, responsive update
  dialog, including headings, lists, links, tables and code blocks. Keep dialog
  actions visible while long release notes scroll.
- Expand release-note handling beyond the previous 1,200-character display
  cutoff; enforce a bounded input size and offer the official release page when
  notes exceed the limit.
- Document Microsoft Store as an available Windows installation option while
  retaining the standalone Windows installer and Debian packages. Distinguish
  Store-managed updates from manual GitHub installer updates.

### Fixed

- Coordinate rapid Live TV channel changes through a single playback engine:
  close the previous source before opening the next and discard superseded
  navigation requests. Ignore held-key repeats and cancel pending navigation
  when the player closes or account access changes.
- Preserve account isolation and effective protected-link expiry when restoring
  sessions, browsing favorites and changing channels.
- Improve playback retry feedback, visibility and resilience to provider
  connection or stream failures without closing the player.
- Fix long release notes appearing as raw Markdown or being silently truncated;
  reject unsafe link destinations and handle missing or invalid content.

### Distribution and verification

- Source version: `0.6.4+1`. The immutable tag `v0.6.4` identifies source
  commit `d9078f636435621e176305b7eb19eb24082fde10`.
- The maintainer reported 434 passing Flutter tests, a clean static analysis,
  and no Dart formatting changes on Debian during release preparation.
- Debian and Windows standalone release installers require separate packaging,
  checksum verification and installation checks before publication. The
  Microsoft Store MSIX update is a separate submission.
- See the [0.6.4 release notes](docs/releases/v0.6.4.md) for user-facing
  details and upgrade instructions.

## [0.6.3](https://github.com/denuczi/DenucziTV/releases/tag/v0.6.3) (Stable)

### Changed

- Add a subtle circular red glow to the dark workspace background, excluding
  the sidebar. The pinned catalog header shares the same background while
  scrolling and resizing; light-mode backgrounds remain unchanged.
- Use red backgrounds with white labels or icons for live badges, movie
  playback, return-to-top controls, and poster hover actions. Episode play
  indicators use a black circle with a white triangle.
- Align episode actions in 40 × 40 logical-pixel areas with uniform 12-pixel
  spacing. Watched episodes use a light-green button background in light mode
  and a dark-green background in dark mode.

### Fixed

- Keep playback errors and retry actions visible inside the video in both
  windowed and fullscreen views. Retrying does not require leaving fullscreen;
  blocked playback hides transport controls and exposes the relevant exit actions.
- Resolve missing My Library covers from the active catalog or provider metadata,
  with a bounded session cache shared by episodes of the same series. Account
  and source changes discard obsolete responses without persisting protected
  artwork URLs or changing saved history.
- Recognize provider artwork in `cover` and `stream_icon` metadata fields when
  the preferred movie-image fields are unavailable.

### Documentation

- Publish a bilingual English/Spanish GitHub Pages landing page with remembered
  language selection, mobile navigation, installation guidance, and non-draggable
  images.
- Add the project banner and improve README navigation, download-table alignment,
  and screenshot presentation.

### Distribution and verification

- Debian amd64 and Windows x64 installers use source version `0.6.3+1`, with
  matching SHA256 files and application tag `v0.6.3`.
- All 364 local Flutter tests and 13 Debian packaging checks passed. The Debian
  upgrade simulation passed on the build system.
- Windows installer workflow [42649741827](https://github.com/denuczi/DenucziTV/actions/runs/42649741827)
  passed formatting, analysis, tests, compilation, packaging, and artifact upload.
- The maintainer confirmed that the generated installers work. See the
  [release notes](docs/releases/v0.6.3.md) for installation and upgrade guidance.

## [0.6.2](https://github.com/denuczi/DenucziTV/releases/tag/v0.6.2) — Stable

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

### Distribution and verification

- Linux amd64 Debian package and Windows x64 setup installer, with SHA256 files.
- Windows installer built from the existing `v0.6.2` application tag using a
  manually dispatched GitHub Actions workflow. It includes the app-local Visual
  C++ runtime, installs per user, and is not Authenticode-signed.
- The maintainer ran 100 update tests and all 343 tests in the full Flutter suite
  successfully during release preparation.
- Windows installer workflow [42524444147](https://github.com/denuczi/DenucziTV/actions/runs/42524444147)
  passed formatting, analysis, Flutter tests, the native release build, installer
  compilation, and artifact upload. The maintainer then confirmed installation,
  application operation, and update checks under a normal Windows user session.

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
