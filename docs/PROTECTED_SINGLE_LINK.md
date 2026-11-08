# Protected Single Link

Protected Single Link is an additional Xtream connection method. It resolves a
permanent link into a verified connection; it never imports an M3U playlist.
Manual Xtream accounts retain their existing playback, download, copying,
export, and account-detail behaviour.

## Using a protected account

Select **Protected Single Link** in **Add account**, then enter an account name
and the permanent HTTP or HTTPS link. Both fields are required. The saved
account exposes its name, synchronisation state, last successful check, and link
expiry. The permanent link, provider address, credentials, and installation
identifier are not displayed after registration. Account names can be changed;
**Update credentials** checks the original link again.

Protected accounts can play and download content while authorised. They cannot
export playlists or copy playback URLs, even when those options are enabled for
manual accounts in Settings. These restrictions are enforced by the functional
export and sharing operations as well as the interface.
In Settings, the copy and export switches are disabled and shown as off while a
protected account is selected, with an explanation in the current language. Saved
preferences are retained and become editable again for manual accounts. The
download switch remains available.

## Redirect contract

The original link must return HTTP 301, 302, 303, 307, or 308. At most four
redirects are accepted. Absolute and relative Location values are supported,
including HTTP/HTTPS protocol changes. Redirect loops, invalid ports,
non-HTTP(S) schemes, embedded URL authority credentials, fragments, control
characters, missing locations, and URLs longer than 8192 characters are rejected.

The terminal destination must end in `/get.php` and contain one non-empty
`username` and one non-empty `password` query parameter. Parameter order does
not matter. `type` and `output` are optional. A path prefix before `/get.php`
is preserved for `player_api.php`. The terminal destination is parsed locally
and is **never requested**.

Each intermediate request is a GET with advisory `Range: bytes=0-0`. The
transport reads response headers only and force-closes the connection without
buffering or draining the body, even if Range is ignored. This avoids relying
on providers implementing HEAD. A remote server can still transmit bytes before
the connection closes; this is not a promise of zero network traffic. Each hop
has a ten-second timeout within a forty-second resolution budget. HTTP errors,
DNS failures, TLS failures, malformed responses, and timeouts produce sanitised
messages without endpoints or credentials. HTTPS certificate checks remain
active; HTTP is allowed without artificial protocol restrictions.

### Effective link expiry

Optional `dtv_expires` is a positive integer Unix timestamp in **seconds UTC**,
for example `1893456000` for 2030-01-01 00:00:00 UTC. Duplicate, empty, negative,
fractional, out-of-range, and non-numeric values are invalid. This parameter is
consumed locally and never forwarded to Xtream. It is independent of
`user_info.exp_date`; missing `dtv_expires` means **Expiration not provided**.

At the deadline, runtime authorisations are revoked, the active catalogue is
withdrawn, playback is stopped and its native playlist cleared, and queued or
active downloads are cancelled. Old credential snapshots cannot start API,
playback, or download operations. Existing transfer retries are also disabled.
Completed downloads and recoverable partial files are retained, together with
the account, permanent link, favourites, history, and progress. The secure
connection is cleared while preserving the original link for later recovery.
If secure cleanup fails, runtime access remains revoked and cleanup is retried.
Startup checks reject expired saved credentials before connecting.

Precise deadline timers operate independently of the 24-hour refresh interval.
Lifecycle resume checks and a one-second wall-clock watchdog cover suspension
and wall-clock changes. No application can execute callbacks while the OS has
suspended its process; revocation is enforced when execution resumes. This is
local application enforcement using the system clock, not DRM or a trusted
remote clock. A later valid authorisation can be restored through manual update
after credentials and the complete catalogue have been verified.

## Identity and HTTP headers

A cryptographically random UUIDv4 is generated once using `Random.secure()` and
stored in the existing operating-system secret store. Concurrent callers share
one generation operation. Updates and account renewals retain the UUID. No MAC,
hardware serial number, hostname, or OS identifier is used. A second per-account
tracking identifier is unnecessary: the permanent URL already distinguishes
links, so no additional identifier is collected.

The versioned header format is:

```text
DenucziTV/<application-version> ProtectedLink/1 Installation/<installation-uuid>
```

**Only the initial request to the permanent link receives this header.** Every
subsequent hop receives the normal application or user-configured User-Agent,
even when it has the same origin. Each hop uses a fresh HttpClient with automatic
redirects disabled. No cookies or Authorization headers are carried between
requests. The identifying header never enters NetworkClient, media_kit,
download requests, image headers, diagnostics, exports, or UI state.

Xtream API, artwork, streams, and downloads retain the normal User-Agent.
There is no EPG-fetching subsystem in the current codebase; any future EPG
integration must use the same ordinary network configuration.

The identifying header is copyable and spoofable. It helps the origin recognise
an installation; it is not cryptographic proof of identity. HTTP exposes headers
and URL tokens to network observers. Open source client-side restrictions do not
protect secrets against someone controlling the machine, debugging memory, or
modifying the application. DenucziTV does not log protected links or credentials,
and does not forward native player errors to the UI. External provider responses
and third-party native libraries remain outside this privacy guarantee.

## Persistence and migration

The public account profile retains its stable ID, name, and explicit connection
type. Existing profiles without a type remain manual Xtream profiles. Protected
profiles have empty public server/username fields. One versioned secure-store
value per protected account contains the original link, resolved credentials,
source generation, link expiry, and check timestamps. New secrets are never
stored in ordinary preferences or SQLite. Linux uses the existing secret-service
integration and Windows uses the existing secure-storage backend. An unavailable
or locked store fails closed; there is no plaintext fallback. The installation
identity is independent of account deletion.

SQLite schema version 2 extends both primary keys from
`(account_id, kind, media_id)` to
`(account_id, source_scope, kind, media_id)`. The upgrade rebuilds both tables,
copies every existing column, assigns the empty legacy scope, recreates indexes,
and drops old tables within sqflite's upgrade transaction. Interrupted migration
rolls back. Manual accounts continue using the empty scope. Do not downgrade to
a version that only understands schema version 1; back up application data before
release testing or downgrade experiments.

Every newly resolved authorisation receives a fresh random source scope,
**including renewals with unchanged server and credentials**. Xtream numeric IDs,
titles, and a matching endpoint do not prove content identity across time. The
current API exposes no verified global identifier for automatic reassociation.
This conservative choice prevents a reused ID from acquiring another film's
progress, but means earlier protected favourites and history become unavailable
after a successful renewal. They remain visible and can be removed; progress and
downloaded files are preserved. There is no heuristic title matching. Reconnecting
using the same cached authorisation retains its scope.

Protected history does not persist artwork URLs, since providers may embed
credentials in image paths. It retains descriptive media metadata and progress.

## Renewal and session continuity

ProtectedAccountService separates link resolution from XtreamApi. It authenticates
and fetches categories and entries for Live TV, Movies, and Series before secure
commit. Invalid entries invalidate a protected candidate instead of silently
publishing a truncated catalogue. A legitimately empty section is allowed. The
active catalogue switches only after validation and persistence succeed. Filters,
search, category selection, and catalogue caches are reset together.

A per-account in-flight future coalesces renewals. Normal refresh is due after
24 hours and checked at startup/resume and during maintenance. Failed automatic
checks have a fifteen-minute cooldown; manual checks have a thirty-second
minimum interval. The attempted timestamp is saved before contacting the origin,
so restarts do not erase backoff. Authentication failures can trigger a bounded
origin refresh. Failed refreshes preserve valid previous access until link expiry.
Expired accounts require explicit update; they do not poll their origins forever.

An ordinary successful refresh supersedes previous grants for **new** operations
but does not revoke an already working stream or download. Players and transfers
retain their captured source. A failed old stream is stopped without mapping its
ID or title onto the new catalogue; the user can close it or explore the updated
catalogue. New actions from stale details and library views are blocked. Existing
downloads never have their URLs silently replaced. Expiry always takes precedence
and revokes old sessions even if a newer catalogue has been activated.

Secure storage mutations are serialised. Renaming changes only public metadata,
so it cannot restore an older secure connection. Expiry cleanup rereads the
current secure authorisation in the mutation queue, preserving a newer valid
commit. Cancelled or removed accounts cannot be recreated by late renewal saves.

## Code map and QA

| Responsibility | Main files |
| --- | --- |
| Account type, secure state, revocable grants | `lib/core/models/account.dart`, `protected_account.dart`, `protected_access_grant.dart` |
| Secure persistence and installation identity | `lib/core/storage/account_store.dart` |
| Header-only redirect resolution | `lib/features/connection/data/protected_link_resolver.dart` |
| Staged validation and bounded renewal | `lib/features/connection/application/protected_account_service.dart` |
| Scheduling, activation, expiry, lifecycle | `lib/core/models/app_controller.dart` |
| Functional sharing policy | `xtream_api.dart`, `playlist_exporter.dart` in `lib/features/library/data/` |
| Source scopes and migration | `lib/features/personal_library/`, `lib/features/library/domain/media_models.dart` |
| Session and transfer cancellation | `lib/features/player/presentation/player_dialog.dart`, `lib/features/downloads/data/download_manager.dart` |
| Form, details, account actions | `lib/features/connection/presentation/`, `lib/features/accounts/presentation/` |
| Localised messages | `lib/l10n/app_en.arb`, `lib/l10n/app_es.arb` |

Regression coverage is added under `test/connection/`,
`test/personal_library/protected_source_migration_test.dart`, and
`test/ui/protected_account_ui_test.dart`. These use fake credentials, injected
transports, mock APIs, temporary SQLite databases, and a local HTTP server test.
Existing tests are retained. No real IPTV provider is needed.

Run on a development machine, using low concurrency on a two-thread system:

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos --fatal-warnings
flutter test --concurrency=1
```

Before publication, also verify Linux and Windows secret-store failure/recovery,
real media_kit playback across normal refresh and expiry, downloads with retained
partial files, system suspend/resume, and English/Spanish layouts in both themes.
Only after automated checks pass, `flutter run -d linux` can verify the desktop UI.
No release build is needed for these checks.

### Verification in the implementation environment

Flutter analysis completed without issues. The full Flutter test command was
attempted but could not start tests because the restricted environment denies
local socket binding required by flutter_tester (`127.0.0.1`, OS error 1). The
attempt also exhausted the limited temporary filesystem while compiling test
listeners and was interrupted after repeated infrastructure failures. Temporary
listeners from that attempt were removed. These are infrastructure failures,
**not passing test results**.
A separate pure-Dart runtime harness passed 118 assertions exercising production
redirect parsing, header isolation, UUID generation, scoped URL policy, and
revocation without sockets. An independent Python sqlite3 check also verified
the production table SQL, legacy data preservation, composite uniqueness, reused
ID isolation, and interrupted-migration rollback. These checks do not replace
the Flutter suite, the sqflite integration test, or desktop platform QA.

### Follow-up regression corrections

A subsequent run on the developer's machine reported 220 passing tests and three
failures: two pending maintenance timers and one controller-expiry timeout. The
two widget tests now give Provider ownership of their controllers, so disposal
cancels timers before Flutter checks teardown invariants. The expiry widget test
creates its fixture inside the fake-async zone, rather than awaiting a storage
queue created in the outer setup zone. It also checks that access remains valid
one microsecond before the deadline and is revoked at the deadline. A standalone
Dart/fake_async reproduction confirmed the cross-zone queue stall and the fixture
creation fix. The corrected Flutter tests still require a rerun outside this
environment's socket restrictions.

### Download feedback verification

The developer subsequently ran the following targeted command locally and
reported **10 tests passed**:

```sh
flutter test --concurrency=1 \
  test/ui/download_feedback_test.dart \
  test/downloads/resumable_download_test.dart
```

This confirms the selected download feedback and resume regressions. It does not
establish that the entire test suite or the protected-account widget tests pass.

## Official references

- [Dart automatic redirect control](https://api.dart.dev/dart-io/HttpClientRequest/followRedirects.html)
- [Dart request cancellation](https://api.dart.dev/dart-io/HttpClientRequest/abort.html)
- [Dart secure randomness](https://api.dart.dev/dart-math/Random/Random.secure.html)
- [HTTP semantics and redirects (RFC 9110)](https://www.rfc-editor.org/rfc/rfc9110.html)
- [Flutter lifecycle observation](https://api.flutter.dev/flutter/widgets/WidgetsBindingObserver-class.html)
- [flutter_secure_storage 11.2.0](https://pub.dev/packages/flutter_secure_storage/versions/11.2.0)
- [media_kit Media and HTTP headers](https://pub.dev/documentation/media_kit/latest/media_kit/Media-class.html)
- [media_kit Player](https://pub.dev/documentation/media_kit/latest/media_kit/Player-class.html)
- [Dio request options](https://pub.dev/documentation/dio/latest/dio/Options-class.html)
