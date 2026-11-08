# Development guide

This guide is for contributors working on DenucziTV's source code. To install
the application, start with the [README download and installation instructions](../README.md#install).

## Requirements

- Flutter **3.47+** and Dart **3.13+**, matching `pubspec.yaml`.
- Git and the native toolchain for the operating system you are building on.
- Python 3 for the optional runner-branding scripts. Pillow is required only
  when regenerating image assets, not for ordinary application builds.

The Linux and Windows runners and `pubspec.lock` are tracked. Keep the lockfile
committed, resolve dependencies with Flutter, and review dependency updates with
the application code. Do not hand-edit dependency resolutions or regenerate the
platform runners during routine development.

## Linux

On Debian/Ubuntu, install the native development dependencies:

```bash
sudo apt update
sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev \
  libstdc++-12-dev libsecret-1-0 libsecret-1-dev libmpv-dev mpv \
  libsqlite3-0 libsqlite3-dev
```

Clone and prepare the project:

```bash
git clone https://github.com/denuczi/DenucziTV.git
cd DenucziTV
flutter pub get
flutter gen-l10n
```

Run the checks, then launch or build the application:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos --fatal-warnings
flutter test
flutter run -d linux
flutter build linux --release
```

Run commands individually and resolve failures before continuing. `flutter run`
starts an interactive development session; exit it before running the release
build. The release bundle is written under
`build/linux/<architecture>/release/bundle/`.

On Fedora, use the equivalent packages, including `gtk3-devel`,
`libsecret-devel`, `mpv-devel`, `sqlite-devel`, CMake, and Clang. Validate the
native library availability for the distribution you target.

To package an existing Linux release bundle as a `.deb`, follow
[Debian packaging](DEBIAN_PACKAGING.md). That guide covers packaging tools,
dependency detection, verification, and distribution compatibility.

## Windows

Build on Windows with a compatible Flutter SDK and Microsoft's C++ desktop
toolchain: Visual Studio or Visual Studio Build Tools, with the desktop C++
workload, MSVC, CMake tools, and a Windows SDK. Visual Studio Code alone does
not provide that toolchain. Android Studio and an Android emulator are not
required for this desktop target.

From PowerShell:

```powershell
git clone https://github.com/denuczi/DenucziTV.git
cd DenucziTV
flutter doctor -v
flutter pub get
flutter gen-l10n
flutter analyze --fatal-infos --fatal-warnings
flutter test
flutter run -d windows
flutter build windows --release
```

Resolve Windows toolchain errors reported by `flutter doctor -v` before building.
Run commands individually; exit the interactive `flutter run` session before
starting the release build.

For x64 builds, the application bundle is normally in
`build/windows/x64/runner/Release/`. Distribute the executable with its DLLs and
`data` directory, and account for the Visual C++ runtime. `flutter build windows`
compiles the application; it does not create or sign a setup installer.

## Architecture

| Concern | Implementation |
| --- | --- |
| UI and navigation | Flutter Material 3, Yaru, Provider/ChangeNotifier |
| Provider API | Dio and typed Xtream models |
| Playback | media_kit/libmpv with native audio and subtitle controls |
| Personal library | SQLite through `sqflite_common_ffi`, scoped per account |
| Preferences | SharedPreferencesAsync |
| Passwords | flutter_secure_storage and the operating system's secret service |
| Application version | package_info_plus, using `pubspec.yaml` metadata |

The source tree groups application features under `lib/features`, shared
infrastructure under `lib/core`, reusable UI under `lib/shared`, and translations
under `lib/l10n`.

`lib/features/personal_library` separates domain, data, application, and
presentation code. Its controller serializes database updates, while the FFI
database package dispatches SQLite operations to a background isolate. Schema
migrations are explicit; no schema generator is required.

See [personal-library behavior](PERSONAL_LIBRARY.md) for account isolation,
progress tracking, catalog refresh, and deletion rules.

## Localization

Flutter's `gen_l10n` workflow is enabled. The source language is English:

- `lib/l10n/app_en.arb`: source strings.
- `lib/l10n/app_es.arb`: neutral Spanish translations.
- `lib/l10n/l10n_ext.dart`: the `context.l10n` UI accessor.
- `lib/core/localization/app_languages.dart`: available language choices.

Generate the Dart localization files with:

```bash
flutter pub get
flutter gen-l10n
```

Generated `app_localizations*.dart` files are ignored by Git. Edit ARB resources
instead. Use ICU plural expressions for quantities and keep Dart identifiers,
comments, and internal log messages in English. Do not use translated strings
as widget keys or routing identifiers.

To add a language, create `lib/l10n/app_<code>.arb`, add its native-name option
to `app_languages.dart`, regenerate the localization files, and extend the
relevant widget tests. The Settings language choice is saved locally.

Translations apply to application-owned UI and recognized errors at the
presentation boundary. Provider titles, descriptions, categories, metadata,
and unknown provider messages are displayed as supplied.

## Branding and native runners

The artwork source is `assets/branding/source/approved_app_icon.png`. The
canonical in-app icon is `assets/branding/denuczitv_app_icon.png`; Windows uses
`assets/branding/denuczitv.ico`. Generated image sizes and native icons are
already included in the repository.

To regenerate the delivered PNG and ICO files deliberately:

```bash
python3 -m pip install Pillow
python3 scripts/generate_brand_assets.py
```

Preserve the approved geometry. The existing generation process makes only the
external black corner matte transparent; it does not redraw the logo or extract
a separate mark from it.

If a Flutter SDK change requires regenerating runners, review the changes
carefully and reapply branding. On Linux, `scripts/bootstrap.sh` performs that
regeneration. On Windows:

```powershell
flutter create --project-name denuczi_tv --platforms=windows,linux .
python scripts/apply_branding.py
```

These commands are maintenance steps, not installation prerequisites. Preserve
native metadata and deliberate CMake configuration changes when reviewing the
result. `apply_branding.py` can be repeated, but it does not replace that review.

Linux desktop launchers need an installed icon and a matching desktop entry;
setting the GTK window icon alone does not register an application-menu entry.
The [Debian packaging script](../scripts/package-deb.sh) handles that integration.

## Verification and contributions

Follow [CONTRIBUTING.md](../CONTRIBUTING.md) for branches, pull requests, and
changelog updates, and [QA.md](QA.md) for automated and manual release checks.
The CI workflow checks formatting, analysis, tests, desktop builds, and Debian
packaging. Compilation and CI success do not replace playback and installation
checks on the target desktop.

Use synthetic data in tests. Never commit real accounts, passwords, session
URLs, exported playlists, downloaded media, or local databases. See
[SECURITY.md](../SECURITY.md) for credential handling and vulnerability reporting.
