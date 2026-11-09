# Windows installer from Linux with GitHub Actions

To install the app, follow the [Windows installation steps](../README.md#windows).
This guide is for maintainers generating an installer.

The manually dispatched `Windows installer` workflow builds a tagged Windows x64
application on GitHub's Windows Server 2022 runner, packages it with Inno Setup 7,
and uploads downloadable artifacts. The maintainer can start it and retrieve the
result from Linux without installing a Windows development environment locally.

It does not create releases, modify tags, execute installers on user machines,
or publish assets automatically. Its repository permissions are read-only.
Artifacts are retained for 14 days and are not update-checker download sources.
Only manually published compatible assets of stable releases are eligible for
the application's update checker.

## Files and source selection

- `.github/workflows/windows-installer.yml`: manual build and artifact upload.
- `scripts/package-windows.ps1`: validates version, source tag, PE architecture,
  runtime files, and packages the application.
- `packaging/windows/DenucziTV.iss`: bilingual per-user installer, with a stable
  AppId for subsequent upgrades.
- `packaging/windows/flutter-toolchain.cmake`: disables optional JNI discovery.

The workflow checks out packaging tools from the selected workflow revision
(normally `main`), and application source separately from `refs/tags/<release_tag>`.
Thus `v0.6.2` need not already contain the newly added packaging infrastructure.
There is no need to move the published tag or rebuild application code from main.
The selected tag must match the stable numeric version in `pubspec.yaml`.

Flutter is pinned to 3.47.9 and Inno Setup to 7.1.1 x64. The downloaded Inno Setup
installer must have a valid Authenticode signature with the publisher identified
on the official download page. The produced DenucziTV installer is unsigned.

GitHub-hosted runners include Java. DenucziTV does not use the optional desktop
JNI bridge, so the workflow passes `CMAKE_TOOLCHAIN_FILE` before a fresh CMake
configuration. The policy disables `find_package(JNI)` without changing tagged
application source or the package cache. A bundle containing `dartjni.dll` is
rejected rather than redistributing an unexpected JVM dependency.

The packager copies the official x64 release CRT from the runner's Visual Studio
2022 installation into the bundle. All runtime files and assets are installed;
PDB debug symbols are excluded. This app-local CRT deployment does not require
the end user to install Visual Studio or a separate global runtime installer.
CRT redistribution remains subject to Microsoft's toolchain license terms.

## Start the workflow from Linux

Commit and push the packaging files to the repository's default branch first.
GitHub requires a manually dispatched workflow to exist on the default branch.
Do not recreate the existing application tag.

```bash
gh workflow run windows-installer.yml \
  --repo denuczi/DenucziTV \
  --ref main \
  -f release_tag=v0.6.3
```

List runs to obtain the ID of the execution you just started:

```bash
gh run list --repo denuczi/DenucziTV \
  --workflow windows-installer.yml --event workflow_dispatch --limit 5
```

Use that numeric ID in place of `RUN_ID`:

```bash
gh run watch RUN_ID --repo denuczi/DenucziTV --exit-status
gh run download RUN_ID --repo denuczi/DenucziTV \
  --name denuczitv-windows-v0.6.3-x64 \
  --dir dist/windows-v0.6.3
```

If the run fails, inspect its log instead of publishing partial output:

```bash
gh run view RUN_ID --repo denuczi/DenucziTV --log-failed
```

The same workflow is available under GitHub's Actions tab: choose **Windows
installer**, then **Run workflow**, branch `main`, input `release_tag=v0.6.3`.
After a successful run, download the artifact listed at the bottom of that run.

## Verify and test the result

The artifact contains:

```text
DenucziTV-Setup-0.6.3-x64.exe
DenucziTV-Setup-0.6.3-x64.exe.sha256
DenucziTV-Setup-0.6.3-x64.build-info.json
```

Verify the checksum from the artifact directory:

```bash
(cd dist/windows-v0.6.3 && sha256sum --check DenucziTV-Setup-0.6.3-x64.exe.sha256)
```

The build-info file records the actual application source commit/tag, numeric
version, build number, architecture, CRT version, installer signature status,
and SHA256. SHA256 is an integrity checksum, not an editor signature.

Transfer the installer to a Windows 10/11 x64 computer for installed-app QA.
No Flutter SDK, Git, Build Tools, or Inno Setup is needed on that test computer.
Test installation, launching from Start, playback, audio, subtitles, downloads,
account persistence, personal library, themes, and languages. Reinstall over the
same application to check account/library preservation and a single uninstall
entry. Check uninstallation with synthetic data. The installer runs per user
under `%LOCALAPPDATA%\Programs\DenucziTV`; it has no user-data deletion rules.

The workflow runs formatting, analysis, Flutter tests and a native release build,
but a headless server does not validate desktop interaction, graphics, audio,
playback compatibility or real installation on a user's Windows machine.
An unsigned installer may show Windows trust/reputation warnings. Do not present
it as signed or disable operating-system protections to pass QA.

## Publish the tested installer from Linux

Only after the run and native installation tests pass:

```bash
gh release upload v0.6.3 \
  dist/windows-v0.6.3/DenucziTV-Setup-0.6.3-x64.exe \
  dist/windows-v0.6.3/DenucziTV-Setup-0.6.3-x64.exe.sha256 \
  --repo denuczi/DenucziTV
```

This attaches the files to the existing release. Do not use `--clobber` to
replace an already published installer. The build-info JSON may be attached as
optional technical provenance. Add Windows installation instructions and the
unsigned status to release notes after actual QA. Preserve the existing Linux
installer and other assets.

If native testing requires application code fixes, create a new application
version and tag rather than silently distributing changed code under v0.6.3.

## Verified 0.6.3 build

[Workflow run 42649741827](https://github.com/denuczi/DenucziTV/actions/runs/42649741827)
passed formatting, analysis, Flutter tests, native compilation, Inno Setup
packaging, and artifact upload.

The build-info records application version `0.6.3+1`, source tag `v0.6.3`,
application commit `816b45fb293065d099128939f50d8f7eb65e5307`, x64 architecture,
Visual C++ runtime `14.44.35211.0`, and signature status `NotSigned`. The downloaded
SHA256 was verified, and the maintainer confirmed that the generated installers
work. See the [release notes](releases/v0.6.3.md).

## Verified 0.6.2 build

[Workflow run 42524444147](https://github.com/denuczi/DenucziTV/actions/runs/42524444147)
completed successfully: formatting, analysis, Flutter tests, Windows compilation,
Inno Setup 7 installation, packaging, and artifact upload all passed.

The generated build-info records application version `0.6.2+1`, source tag
`v0.6.2`, application commit `bfa53a16ef557d8c574414649bf0c02c3067c56e`, x64
architecture, Visual C++ runtime `14.44.35211.0`, and signature status `NotSigned`.
The maintainer verified the downloaded checksum and reported that installation,
application operation, and update checks work in a normal Windows user session.

These results apply to that artifact. Each future release still needs the
workflow checks and installed-app QA described above. The exact Windows desktop
version was not recorded; do not infer coverage of every supported Windows version
or of every manual test case from the build result.

## Official references

- [Manually running a GitHub workflow](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)
- [Windows Server 2022 runner inventory](https://github.com/actions/runner-images/blob/main/images/windows/Windows2022-Readme.md)
- [Inno Setup downloads](https://jrsoftware.org/isdl.php)
- [Inno Setup compiler options](https://jrsoftware.org/ishelp/topic_compilercmdline.htm)
- [CMake toolchain environment variable](https://cmake.org/cmake/help/latest/envvar/CMAKE_TOOLCHAIN_FILE.html)
- [Microsoft app-local runtime deployment](https://learn.microsoft.com/en-us/cpp/windows/walkthrough-deploying-a-visual-cpp-application-to-an-application-local-folder?view=msvc-170)
