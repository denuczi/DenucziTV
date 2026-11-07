# Personal library

The personal library stores favorites, watch history, and playback progress in a
local SQLite database. Records are scoped to the saved provider account and are
not synchronized between devices.

## Behavior

- Movies and series can be favorited from their detail views. Individual episodes
  are tracked for viewing rather than favorited separately.
- Playback progress is saved approximately every ten seconds of video position,
  as well as on pause and player close. Resume depends on a meaningful timeline
  and a seekable stream.
- Automatic advancement through a series queue marks the completed episode as
  watched. Manually skipping an episode does not mark it complete.
- Live TV does not create watch history or resume positions.
- A playback session retains the identity of the account that started it.
- A successful catalog refresh can mark removed content as unavailable while
  retaining history. A failed or offline refresh does not remove history.
- Clearing watch history preserves favorites and downloaded files. Removing a
  saved provider account clears that account's personal-library records.

## Storage and privacy

The implementation lives in `lib/features/personal_library`, with domain, data,
application, and presentation layers. The repository uses `sqflite_common_ffi`;
schema migrations are explicit.

The database does not store account passwords or complete stream URLs. It is not
encrypted by the application. Treat local profile data as private and do not
attach database files to bug reports. See [SECURITY.md](../SECURITY.md).

## Verification

Use synthetic accounts to verify isolation, favorites, progress persistence,
account removal, and unavailable content. The automated tests are in
`test/personal_library`; manual release checks are in [QA.md](QA.md).
