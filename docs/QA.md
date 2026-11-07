# Quality assurance

Complete these checks before publishing a release. Record the commit, Flutter
version, operating system, commands, and results in the release notes or pull
request. A passing CI run does not replace playback checks on a real desktop.

## Automated checks

```bash
flutter --version
flutter pub get
flutter gen-l10n
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos --fatal-warnings
flutter test --coverage
```

Build on each target operating system:

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
