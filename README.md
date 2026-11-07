# DenucziTV

**DenucziTV** is an open-source IPTV player for **Windows** and **Linux**. It works with user-provided Xtream-compatible services. It does **not** distribute channels, subscriptions, movies, or playlists.

- **Author:** Ignacio Sanguina
- **Repository:** https://github.com/denuczi/DenucziTV
- **License:** MIT
- **Status:** v0.5.3 development candidate — not a tested release.

## Features

- Multiple saved Xtream accounts, validation, account metadata, and automatic reconnection after an ordinary restart.
- Live TV, movies, series, searchable categories, series/episode browser, and native playback via media_kit/libmpv.
- Audio track selection, internal and external subtitle selection, and video-track selection when the stream exposes those tracks. Continuous ABR is **not implemented**.
- Direct-file downloads with safe naming, account-scoped deduplication, saved folders, retry, retained partial downloads and HTTP Range resume when the provider supports it.
- **My Library**: favorites, Continue Watching, Watch History, manually mark episodes watched/unwatched, remove progress entries, and resume or restart playback.
- Personal-library records are stored locally in SQLite, separately for each saved provider account, without stream URLs or credentials. Favorites and history are not synchronized to other devices.
- Automatic versioned User-Agent (`DenucziTV/<installed version>`) or an explicitly saved custom header. Custom values are not overwritten during application updates.
- Yaru/Material desktop UI with light/dark/system appearance and separate opt-in download/link/export actions.
- Localization with official Flutter ARB resources: English (source language) and neutral Spanish, with System/English/Español choice persisted in Settings. The user's provider metadata is not machine-translated.
- Account-scoped media dialogs and saved-account actions prevent overlapping routes from rapid clicks; catalog headers stay truly centered and display specific counts (channels, movies, series).
- Brand theme uses contrast-aware black/white/red accents and restrained sidebar/header gradients; semantic success and warning colors are retained.


## UI localization and future languages

Flutter's official `gen_l10n` workflow is enabled (`flutter: generate: true`).
The source of truth is `lib/l10n/app_en.arb`; Spanish translations live in
`lib/l10n/app_es.arb`. Build with `flutter pub get && flutter gen-l10n`.
The generated `app_localizations*.dart` files are deliberately not committed
to the repository. `lib/l10n/l10n_ext.dart` exposes `context.l10n`
for user-visible labels. Use ICU plural expressions for quantities, not
hand-assembled English suffixes. Keep Dart APIs, log messages and comments in English.

The Settings > Language control allows following the operating system (default),
English, or Español; a selection is stored as a non-sensitive preference.
To add a locale: create `lib/l10n/app_<code>.arb`, add its native-name option to
`lib/core/localization/app_languages.dart`, run `flutter gen-l10n`, and extend
localized widget tests. Avoid using translated labels as widget keys or routing IDs.

English/Spanish strings apply to application-owned UI; recognized application
errors are translated at the presentation boundary without changing provider
responses or the messages retained by internal services. Unknown provider
messages are displayed unchanged. Provider-supplied movie titles, synopsis,
stream metadata and Xtream category names are not translated.

## Architecture

| Concern | Implementation |
| --- | --- |
| UI/navigation | Flutter Material 3 + Yaru, Provider/ChangeNotifier |
| Provider API | Dio and typed Xtream models |
| Playback | media_kit/libmpv; native audio and subtitle controls |
| Personal library | SQLite via `sqflite_common_ffi`, repository abstraction, account-scoped controller |
| Preferences | SharedPreferencesAsync |
| Passwords | flutter_secure_storage / OS secret service |
| Package version | package_info_plus, sourced from pubspec metadata |

`lib/features/personal_library` contains separate domain, data, application and presentation layers. Database updates are serialized by the application controller. SQLite operations are dispatched to a background isolate by the FFI database package. No schema generator is needed for this version; migrations are explicit. The repository interface allows a later transition to Drift without rewriting the UI.

## Build from source

Install **Flutter 3.47+ / Dart 3.13+** and the native desktop toolchain. On Debian/Ubuntu:

```bash
sudo apt update
sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev \
  libstdc++-12-dev libsecret-1-0 libsecret-1-dev libmpv-dev mpv \
  libsqlite3-0 libsqlite3-dev

git clone https://github.com/denuczi/DenucziTV.git
cd DenucziTV
flutter pub get
flutter gen-l10n
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos --fatal-warnings
flutter test
flutter run -d linux
flutter build linux --release
```

On Fedora, use the equivalent development packages (such as `gtk3-devel`, `libsecret-devel`, `mpv-devel`, `sqlite-devel` and CMake/Clang). Validate the libmpv library for the distribution. On Windows, use Flutter's Windows desktop toolchain and Visual Studio C++ workload:

```powershell
git clone https://github.com/denuczi/DenucziTV.git
cd DenucziTV
flutter pub get
flutter gen-l10n
flutter analyze --fatal-infos --fatal-warnings
flutter test
flutter run -d windows
flutter build windows --release
```

The repository includes the Linux and Windows platform runners and `pubspec.lock`.
Keep the lockfile committed and review dependency updates with the application code.
Do not hand-edit dependency resolutions. If the platform runners need to be
regenerated, run `scripts/bootstrap.sh` on Linux, or run `flutter create
--project-name denuczi_tv --platforms=windows,linux .` followed by
`python scripts/apply_branding.py` on Windows. Review the resulting changes before
committing. Do not commit actual accounts, passwords, session URLs, exported
playlists, downloaded media, or local SQLite databases.

## Debian package

For a native Debian/Ubuntu package built from the Linux release bundle, see
[Debian packaging](docs/DEBIAN_PACKAGING.md).

## Personal-library behavior

- Favorite movies and series from their detail views. Episodes are tracked for viewing, not favorited individually.
- Playback progress is saved approximately every ten seconds of video position, plus pause and player close. Resume is offered when the saved position is meaningful and the video is seekable.
- An episode automatically advancing in a series queue is recorded as watched. Manually skipping does not mark it complete.
- The playback session keeps its original account identity even if the user changes accounts elsewhere.
- Live TV is not recorded in watch history and does not support resume.
- My Library displays only records associated with the currently selected account. A fully retrieved provider catalog can mark removed movies/series as unavailable **without deleting** historical data. An offline or failed catalog request does not remove history. Content may remain visible until the relevant catalog is successfully refreshed.
- Clearing Watch History does not delete Favorites or downloaded files. Removing a provider account clears its local personal-library records.

## Limitations and release checks

- This development snapshot is not a verified release. Check the GitHub Actions results and run the manual checks in [QA](docs/QA.md) before publishing a release.
- Progress cannot be reliably resumed for live streams, streams with no meaningful timeline, or servers refusing seeks. Saved position is retained when a seek fails.
- Network interruptions and an abrupt power loss may lose the most recent unsaved seconds. Video decoding, HLS variants and subtitling depend on the provider and installed native libraries.
- Validate fresh SQLite creation, separate account histories, repeated player open/close, series autoplay, and a build on both target platforms.
- Because the old development bundle did not include a stable packaging identity, this release is intended for a clean development installation; do not overwrite an existing OS installation without a backup.

See `docs/PERSONAL_LIBRARY.md`, `docs/QA.md` and `SECURITY.md` for further details.

## Contributing and tracking changes

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow and required
checks. Documentation, issue reports, and pull requests use standard English.
The application also supports Spanish through its localization resources.

Use [GitHub Issues](https://github.com/denuczi/DenucziTV/issues) for bugs and feature
requests, and pull requests for proposed changes. Record user-visible changes in
the Unreleased section of [CHANGELOG.md](CHANGELOG.md). The existing GitHub Actions
workflow checks formatting, analysis, tests, and desktop builds.

## License

DenucziTV is distributed under the [MIT License](LICENSE). Dependency licenses
remain applicable to their respective packages. Use only providers and content
you are authorized to access.

## Brand assets

All native and in-app icons are derived from the **approved artwork** at
`assets/branding/source/approved_app_icon.png`. The artwork is not redrawn,
cropped into a separate mark, or processed with background-color extraction.
Only its external black corner matte is made transparent; the geometric logo is
unchanged. There is one canonical icon at
`assets/branding/denuczitv_app_icon.png`, used by both the Flutter sidebar/Settings
and the GTK window. Flutter decodes it at the current device pixel ratio.

Windows uses the multi-size `assets/branding/denuczitv.ico`, generated from the
same approved artwork. To regenerate all delivered PNG sizes and ICO during
development, install Pillow and run:

```sh
python3 -m pip install Pillow
python3 scripts/generate_brand_assets.py
```

No Python image libraries are needed to build or run the Flutter application.
After `flutter create`, run `python3 scripts/apply_branding.py` (Windows:
`python scripts/apply_branding.py`) to apply native window icons; the script is
repeatable. Linux launchers also need a `.desktop` entry with matching `Icon=`
and an installed icon for KDE/GNOME to select the proper dock/task-manager icon
when packaged. The GTK window icon alone does not register a desktop launcher.

The application is still a development candidate: perform actual
`flutter analyze`, `flutter test`, `flutter build linux`, and (on Windows)
`flutter build windows` before publishing a release.
