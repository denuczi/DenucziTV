# Contributing to DenucziTV

DenucziTV is a Flutter desktop IPTV player for Linux and Windows. Contributions
are welcome under the [MIT License](LICENSE).

## Before you start

- Search existing issues before opening a bug report or feature request.
- Discuss larger changes in an issue before starting implementation.
- Use standard English for documentation, issues, and pull requests. Keep code
  identifiers and comments in English. Application translations belong in ARB files.
- Use synthetic provider data in examples and tests. Never include real accounts,
  credentials, stream URLs, playlists, or copyrighted media.
- Report security vulnerabilities as described in [SECURITY.md](SECURITY.md).

## Development setup

Follow the platform requirements and installation steps in [README.md](README.md).
Fork the repository if you do not have write access, clone your fork, and create
a branch from `main`:

```bash
git switch -c fix/short-description
flutter pub get
flutter gen-l10n
```

Platform runners and `pubspec.lock` are tracked. Avoid regenerating runners for
routine changes. Commit intentional dependency changes together with the updated
lockfile. Generated localization files, SDK caches, builds, and local databases
are ignored.

## Verification

Run these commands before opening a pull request:

```bash
dart format lib test
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

Build and smoke-test the desktop platform affected by your change:

```bash
flutter build linux --release
# On Windows:
flutter build windows --release
```

See [docs/QA.md](docs/QA.md) for manual checks. Add meaningful regression coverage
for behavior changes. If you cannot run a check, state that in the pull request.

## Pull requests and change history

Keep each pull request focused. Describe the problem, the resulting behavior,
related issues, and the checks you ran. Screenshots are useful for interface
changes, provided they contain no private provider information.

Add user-visible changes to the appropriate section under `Unreleased` in
[CHANGELOG.md](CHANGELOG.md). Use clear commit messages, such as
`Fix download resume after a network interruption`. Do not invent release dates
or mark unverified development snapshots as released.

When preparing a release, move the relevant Unreleased entries into a versioned
section, update `pubspec.yaml` as needed, complete the QA checks on both platforms,
and create the corresponding Git tag and GitHub release after validation.
