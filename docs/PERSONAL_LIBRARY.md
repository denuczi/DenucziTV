# Personal library

The personal library stores favorites, watch history, and playback progress in a
local SQLite database. Records are scoped to the saved provider account and are
not synchronized between devices.

## Behavior

- Live TV channels can be favorited from their poster cards and player. Movies
  and series retain their existing favorite controls. Individual episodes are
  tracked for viewing rather than favorited separately.
- Favorites in My Library are grouped by Live TV, movies, and series. Each
  account retains its own list; switching accounts never merges collections.
- Playback progress is saved approximately every ten seconds of video position,
  as well as on pause and player close. Resume depends on a meaningful timeline
  and a seekable stream.
- Automatic advancement through a series queue marks the completed episode as
  watched. Manually skipping an episode does not mark it complete.
- Live TV does not create watch history or resume positions.
- A playback session retains the identity of the account that started it.
- A complete and successful catalog refresh may mark missing saved channels,
  movies, or series as unavailable without deleting favorites or history.
  Failed or empty non-protected responses never establish absence.
- Clearing watch history preserves favorites and downloaded files. Removing a
  saved provider account clears that account's personal-library records.

## Storage and privacy

The implementation lives in `lib/features/personal_library`, with domain, data,
application, and presentation layers. The repository uses `sqflite_common_ffi`;
schema migrations are explicit.

The database does not store account passwords or complete stream URLs. It is not
encrypted by the application. Treat local profile data as private and do not
attach database files to bug reports. See [SECURITY.md](../SECURITY.md).

### Library artwork cache

Saved and recently watched items have an on-disk artwork cache under the
application-support directory (`denuczi_tv/artwork_cache`). It stores only
validated, bounded image bytes. Cache paths derive from opaque account,
source-scope and media identities; provider artwork URLs, access tokens and
credentials are never written to the cache. Artwork is requested only for
personal-library items, not every catalog entry.

Images expire after 72 hours. The cache limits each image to 2 MiB, concurrent
network requests to three, and total storage to 120 MiB / 600 files. A saved
image can appear before the provider catalog loads, including while offline.
First-time covers still require a successful network request. Removing the last
favorite/history reference deletes its cached image; deleting an account
removes that account's cache directory. Protected content playback authorization
is independent from cached artwork availability.

## Verification

Use synthetic accounts to verify isolation, favorites, progress persistence,
account removal, and unavailable content. The automated tests are in
`test/personal_library`; manual release checks are in [QA.md](QA.md).

## Favorites search and account-scoped removal

My Library is the default workspace. Restoring an existing account authenticates
without fetching the Live TV catalog; the first explicit visit to Live TV loads
its categories and channels. Protected links still enforce their access grants,
expiration and source generation. Artwork for saved items may be fetched
individually, without loading the full catalog.

The Favorites view filters saved entries locally by content kind and title.
Live TV artwork and titles open available channels directly. The separate
playback button and remove action remain available.

The Remove all favorites command requires confirmation and deletes favorites
for the active account only. It does not delete watch history, progress,
downloads or another account's data. Cached artwork is removed only when it
is no longer referenced by watch activity.
