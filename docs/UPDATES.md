# Stable update checker (0.6.2)

DenucziTV 0.6.2 adds stable-release discovery and assisted download for desktop.
It leaves the app running and opens an official installer download in the system
browser. Installation remains the user's choice. It never executes an installer,
requests administrator access, replaces application files, or restarts the app.
Versions before 0.6.2 predate this feature and need a manual upgrade first.

## Architecture and audit

The existing entry point already obtains package information before creating the
IPTV controller. Settings ends with credits, and the shell switches workspaces
without pushing routes. Media/account dialogs use Navigator routes and the
existing DialogLaunchGuard. Localisation uses English and Spanish ARB files.
No equivalent update checker existed.

The feature reuses Dio, package_info_plus, shared_preferences, url_launcher,
Provider, the dialog guard, the theme, and notification system. No dependencies
or native runner changes are added.

| Responsibility | Location under `lib/features/updates/` |
| --- | --- |
| SemVer precedence and stable-release/asset policy | `domain/semantic_version.dart`, `domain/stable_release.dart` |
| Isolated GitHub transport and bounded pagination | `data/github_release_api.dart` |
| Process architecture and Linux distribution detection | `data/update_platform.dart` |
| Non-sensitive timestamps and postponement | `data/update_preferences.dart` |
| Single-flight checks, eligibility, session state, URL launching | `application/update_controller.dart` |
| Startup interaction and route safety | `presentation/startup_update_listener.dart` |
| Modal and Settings feedback | `presentation/update_dialog.dart`, `software_update_controls.dart`, `update_labels.dart` |

`main.dart` owns the update controller through Provider. Its network and state
are independent of AppController and its account credentials. The UI coordinator
only observes account activity and download counts to avoid interruption. The
Settings section is placed directly above the existing credits.

## Stable-only release policy

The checker requests the public REST release list at:

```text
https://api.github.com/repos/denuczi/DenucziTV/releases?per_page=100&page=1
```

It filters explicitly for `draft: false`, `prerelease: false`, valid stable SemVer
tags, published metadata, and the exact official repository URL. SemVer tags with
prerelease identifiers are excluded even if incorrectly marked as full releases.
Titles and descriptions never establish stability. CI artifacts and source
archives are not installer candidates. There is no channel selector.

The list is paginated with fixed local page URLs, not untrusted Link redirects.
The highest comparable stable version is selected across the complete retrieved
history, regardless of publication order. Requests have bounded connection,
response and overall timeouts; a page is limited to 4 MiB and history to ten pages
of 100 releases. Exceeding a bound is an error rather than a result based on an
incomplete list. There is no automatic retry loop.

GitHub's `/releases/latest` excludes drafts and prereleases but uses latest-release
ordering rather than guaranteeing the greatest SemVer version. It can return 404
when no full release exists. This implementation deliberately uses the list
instead: an empty list or a list containing only prereleases is a successful
`noStableRelease` result. A 404 from the list itself
is a fetch/repository-access error and is not reported as up to date.

## Installed version and comparison

The installed version and build number come from `PackageInfo.fromPlatform()`.
The legacy AppIdentity fallback used elsewhere is never an update-comparison
source. Unreadable package metadata disables update offers with a retryable
explanation rather than guessing a version.

Comparison follows SemVer 2.0, including numeric components and prerelease
precedence. A leading lowercase `v` is accepted. Build metadata does not affect
precedence: `0.6.2+1` equals `v0.6.2`; `0.6.2-rc.1` is older than `0.6.2`.
`0.6.10` is newer than `0.6.2`. Invalid tags are ineligible.

A prerelease installed as plain `0.6.2+1` cannot be distinguished from a stable
package with that same version using package metadata alone. Changing a GitHub
release flag does not justify forcing a same-version update. Maintainers should
use explicit package versions such as `0.6.3-rc.1+1` for future candidates, then
`0.6.3+1` for the stable build. Otherwise publish a greater application version
when a replacement should be offered.

## Automatic checks and postponement

The startup listener starts asynchronously after the first frame. The account
initialisation/catalogue paths do not await it. A successful check timestamp is
persisted, including a successful result with no stable releases. Another
startup check is due after 24 hours. A future timestamp caused by clock changes
is treated as due. No polling timer or persistent worker is introduced.

One in-flight request is shared by concurrent callers. Only the startup result
can claim one unsolicited modal for that controller's application session.
Rebuilds, theme/locale changes, workspace navigation, account switching, and
closing the player do not trigger additional automatic presentation.

The listener suppresses that session's automatic prompt if the user interacts
before completion, enters another route, manually authenticates an account, or
starts a download. Automatic account restoration blocks a prompt while active;
if it finishes before the result arrives and no user interaction occurred, the
startup result may still be presented safely. A result received during restoration
is suppressed rather than deferred. The result remains visible in Settings. It is not queued
for later presentation after playback ends. Manual checks remain available and
may explicitly open the modal again; the session limit governs unsolicited prompts.

**Maybe later**, Escape, barrier dismissal, and the close button immediately close
the modal and asynchronously store the postponed version and a seven-day window.
No download starts, and a pending download verification is cancelled. The same
or an older postponed candidate is suppressed during
that interval; a genuinely higher version may be announced at a subsequent due
startup. Manual checks bypass postponement. Invalid timestamps cannot create an
indefinite lockout. A preference-store failure leaves session suppression intact
and produces a Settings warning that persistence may be unavailable.

## Compatible installers and official links

The Linux naming convention is taken from `scripts/package_deb.py` and the
published Debian packages. Linux downloads require an x64 process ABI and a system
identifying as Debian/Ubuntu or declaring that family in `/etc/os-release`.

Accepted examples for a fictional stable `v0.6.3` release:

```text
denuczitv_0.6.3+1-1_amd64.deb
DenucziTV-Setup-0.6.3-x64.exe
```

The Windows installer follows the naming contract
`DenucziTV-Setup-<version>-x64.exe` (an optional numeric `+build` is accepted).
The 0.6.2 installer was generated from the application tag and tested by the
maintainer; see [Windows packaging](WINDOWS_PACKAGING.md).
A bare `denuczi_tv.exe`, ZIP, ARM64 package, mismatched version, or unfamiliar
filename is not silently treated as a supported installer. Format and architecture
selection does not guarantee every Debian/Ubuntu version satisfies native library
dependencies; the system package manager remains responsible for installation.

Only uploaded, non-empty assets with exact HTTPS browser-download URLs under
`github.com/denuczi/DenucziTV/releases/download/<tag>/<asset>` are eligible.
Release details must use the matching official `/releases/tag/<tag>` URL. User
information, query strings, fragments, alternate ports, other repositories,
lookalike hosts, and external URLs are rejected before system launching.

The highest stable version is retained even if its compatible installer is
missing. The dialog explains that limitation and offers official release notes,
not a package from an older version or another platform. Immediately before a download, the checker fetches the selected tag again and
revalidates its stable status and compatible assets. A withdrawn release or a
release changed to prerelease is not downloaded. Every launch also checks URL
eligibility; browser failures leave the dialog open with a localised error.

These checks establish source and platform selection, not cryptographic installer
verification. Unattended installation, package signatures, integrity validation
of downloaded bytes, and Windows/Linux installation behaviour require a separate
future design. No such installation system is included in 0.6.2.

## Privacy and UI

GitHub receives a separate fixed `DenucziTV-UpdateChecker/1` User-Agent and public
API headers. The production client has no account store, cookies, authorization,
streaming User-Agent, permanent links, or installation identifiers. Automatic
failures are quiet; manual failures have localised, actionable messages.

Only the last successful timestamp and the postponed version/time window are
stored. Release responses and download URLs are not persisted. A failed query
never produces an up-to-date result. Latest stable metadata is kept only in
memory when known; a recent timestamp alone does not fabricate availability.

Release notes are untrusted plain text, bounded to 1,200 code points and displayed
in scrollable content. No HTML, scripts, Markdown links, or commands are executed.
The dialog uses neutral theme surfaces, an explicit secondary action, focusable
controls, Escape handling, and layouts for narrow desktop windows. Every fixed UI
string is supplied by the existing English/Spanish ARB system.

## Local tests and preview

All automated tests use fictional releases, mocked HTTP/launchers, controlled
clocks, and isolated preferences. Never publish a fake stable release or change a
real prerelease flag to exercise the update modal.

```sh
flutter gen-l10n
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze --fatal-infos --fatal-warnings
flutter test --concurrency=1 test/updates
flutter test --concurrency=1
```

A development-only desktop preview uses the same modal with fake API data and
in-memory preferences. It performs no real network checks, browser launches, or
installation. The download button deliberately demonstrates launch failure.

```sh
flutter run -d linux -t tool/update_preview.dart
flutter run -d linux -t tool/update_preview.dart \
  --dart-define=UPDATE_PREVIEW_LANGUAGE=es \
  --dart-define=UPDATE_PREVIEW_DARK=true
```

The preview is a separate entry point and is not included in the normal app.
Manual platform QA should also cover the real browser, native package metadata,
Windows x64, Debian/Ubuntu x64, and suppression during actual playback/downloads.

## Verification record for 0.6.2

The maintainer ran **100 update tests and all 343 tests in the full suite**
successfully during release preparation, and checked the Linux modal preview.
The recorded implementation analysis and localisation generation also passed.

[Windows installer workflow 42524444147](https://github.com/denuczi/DenucziTV/actions/runs/42524444147)
subsequently passed formatting, analysis, Flutter tests, native compilation and
Inno Setup packaging. The maintainer confirmed that the installed Windows app
and manual update checks work in a normal user session.

These are recorded results for 0.6.2, not a substitute for testing subsequent
changes. Future releases must repeat automated checks and native QA, including
browser launching, active-playback suppression and installation behaviour.

## Official references

- [GitHub REST releases: listing and latest-release semantics](https://docs.github.com/en/rest/releases/releases)
- [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html)
- [package_info_plus metadata](https://pub.dev/documentation/package_info_plus/latest/package_info_plus/PackageInfo-class.html)
- [Dio response streaming](https://pub.dev/documentation/dio/latest/dio/ResponseType.html)
- [System URL launching](https://pub.dev/documentation/url_launcher/latest/url_launcher/launchUrl.html)
