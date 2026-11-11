# Quality assurance

Complete these checks before publishing a release. Record the commit, Flutter
version, operating system, commands, and results in the release notes or pull
request. A passing CI run does not replace playback checks on a real desktop.

## Automated checks

Pushes to `main` skip Flutter Desktop CI when every changed file is Markdown,
under `docs/`, or under `demo/`. A push containing any other file still runs the
full workflow, even when documentation changes are included. Pull requests
continue to run all checks so required checks are reported consistently.

To run the full CI manually on `main`:

```bash
gh workflow run ci.yml --repo denuczi/DenucziTV --ref main
```

The Windows installer workflow is separate and remains manually dispatched. The
Microsoft Store MSIX workflow and its QA/WACK checklist are separate too; see
[MICROSOFT_STORE.md](MICROSOFT_STORE.md).

For local verification, run:

```bash
flutter --version
flutter pub get
flutter gen-l10n
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze --fatal-infos --fatal-warnings
flutter test --concurrency=1 --coverage
```

Build Linux locally and Windows on a Windows host, or use the
[Windows installer workflow](WINDOWS_PACKAGING.md) from Linux:

```bash
flutter build linux --release
# On Windows:
flutter build windows --release
```

## Desktop smoke checks

Use only authorized content and synthetic credentials in shared evidence.

- Launch a clean installation on Linux and Windows. Verify the application name,
  icon, window layout, and light, dark, and system appearance.
- Switch between System, English, and Spanish, then restart and check persistence.
- Add two accounts, validate connection errors, restart, switch accounts, and
  remove an account. Check that private credentials do not appear in diagnostics.
- Browse live TV, movies, series, categories, and search. Open and close media
  dialogs repeatedly, including rapid repeated clicks.
- Play authorized live and on-demand content. Check pause, seeking, fullscreen,
  audio tracks, subtitles, unavailable streams, and repeated player open/close.
- Create a fresh library database. Favorite and unfavorite movies and series;
  check that records remain isolated between accounts.
- Save playback progress, restart, resume, and restart playback from the beginning.
  Check series autoplay and manual watched/unwatched actions.
- Refresh a catalog with removed items, then simulate a failed refresh. Confirm
  that history is retained and that clearing history preserves favorites.
- Download a direct file; cancel, retry, interrupt, and resume it against a server
  supporting HTTP Range. Check duplicate handling, unavailable folders, and disk
  errors. Confirm that removing history does not delete downloaded files.
- Check exported playlists and copied links locally. They may contain credentials
  and must not be attached to public issues.

## Protected Single Link checks

Use fake credentials and controlled endpoints for shared evidence. Do not record
permanent links, provider secrets, or installation identifiers in logs or reports.

- Keep a manual and a protected account saved together. Verify copying/export
  works for the manual account and is unavailable with an explanation for the
  protected account. Downloads remain available for both.
- Connect through HTTP/HTTPS redirects. Confirm only the initial permanent-link
  request carries identification and the final get.php URL is parsed, not fetched.
- Connect with an empty section cache. Verify only the entry section loads, other
  sections load on navigation, and returning to a cached section avoids refetching.
- Renew while playing and downloading. Keep working old sessions on their original
  sources; new operations use the new generation. Reused IDs must not reopen
  unrelated content or inherit another generation's history or progress.
- Simulate a failed visible-section validation. Preserve the previous connection
  and catalog while its link remains valid. A failing unvisited section reports
  its own error when opened without exposing old catalog entries.
- Reach a fixed dtv_expires deadline during playback and a transfer. Verify both
  stop, new access is blocked, and history, favorites, progress, completed files,
  and recoverable partial files remain. Repeat after restart and suspension.
- Supply a later valid authorization through the same permanent link and verify
  recovery only after credentials and the entry section have been validated.

## Live TV and personal-library checks (0.6.4)

- Verify numeric selection in the player with the main keyboard and numeric
  keypad. Wait five seconds after the final digit; use Enter to confirm early,
  Backspace to edit and Escape to cancel. Invalid channel numbers must not
  terminate the current stream.
- Verify `Up`/`Down` and `W`/`S` channel navigation from both windowed and
  fullscreen playback. Repeated key presses must not create duplicate players,
  and channel numbering must remain stable across search/category filters.
- Check the high-contrast channel banner with a missing logo, a long title,
  a small window and both light/dark themes. It must only appear for keyboard
  channel changes, not for initial playback or unrelated media.
- Check My Library on startup without an eager Live TV catalog request. Save
  Live TV favorites, filter/search by type, clear favorites after confirmation,
  and confirm history/downloads and other accounts remain unaffected.
- Verify the Markdown update modal with long notes, malformed links, a narrow
  window and both languages. Actions must remain reachable while content scrolls.

## Stable update checker checks (0.6.2)

Run `flutter test --concurrency=1 test/updates` and use the isolated preview in
[UPDATES.md](UPDATES.md). Never publish fictional stable releases for testing.

- Check that prereleases/drafts and source archives are excluded; an empty stable
  channel is informative, and network failure is never labelled up to date.
- Check English/Spanish, both themes, a narrow window, keyboard focus, Escape,
  close/barrier dismissal, launch failure, and missing compatible installers.
- Start with a due check, then enter playback, download, or authentication before
  it completes. No automatic modal may interrupt or reappear afterwards.
- Postpone, restart within seven days, and verify suppression for that version;
  a manual check must still work. Correct the system clock and test timestamp
  recovery. Verify disposal cancels the checker without late widget updates.
- Run the installed Windows application as a normal user and verify update
  checks work without requiring administrator privileges.
- Verify package metadata and browser download behaviour on Linux and Windows;
  DenucziTV must remain running and must never execute the installer.

## Release record

Use the following fields when recording results:

```text
Commit:
Application version:
Flutter / Dart version:
Linux distribution and version:
Windows version:
Automated checks:
Manual checks:
Known limitations:
```
