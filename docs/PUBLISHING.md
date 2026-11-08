# Publishing source and releases

This guide is for maintainers. To install DenucziTV, use the
[download and installation instructions](../README.md#download).

Run the commands from the repository root in a normal terminal with network
access and a writable `.git` directory. Installers are release assets: keep
`dist/` out of source commits.

## Current stable release

[Version 0.6.2](https://github.com/denuczi/DenucziTV/releases/tag/v0.6.2) uses these
installer filenames:

| Platform | Installer | Checksum |
| --- | --- | --- |
| Debian / Ubuntu x64 | `denuczitv_0.6.2+1-1_amd64.deb` | `denuczitv_0.6.2+1-1_amd64.deb.sha256` |
| Windows x64 | `DenucziTV-Setup-0.6.2-x64.exe` | `DenucziTV-Setup-0.6.2-x64.exe.sha256` |

The release and tag already exist. Do not recreate them to add a platform asset
or update the description. Keep earlier prereleases available as history.

## Authentication and source review

```bash
gh auth status
gh repo view denuczi/DenucziTV
git status
git remote -v
git diff --check
```

If authentication fails, use `gh auth login --hostname github.com`.
Review and commit only the intended source, documentation, version metadata and
tests. Exclude local credentials, configuration, databases and build output.
Keep `pubspec.lock` and the native runners tracked. Do not overwrite remote
history to resolve a rejected push.

## Prepare a new application release

The examples in this section use **0.6.3**, a future version. They are a template,
not instructions to publish the existing 0.6.2 again.

1. Choose an unused version and set `pubspec.yaml`, for example `0.6.3+1`.
   The packagers read it directly. Selecting a filename for package tests does
   not change the application version.
2. Update the changelog and create the new English release notes file, such as
   `docs/releases/v0.6.3.md`. Describe user-visible changes, available platforms,
   installation steps and known limitations. Record actual validation results.
3. Complete [QA.md](QA.md), including formatting, analysis and the full test suite.
   Use `flutter test --concurrency=1` to reduce memory pressure on a small machine.
4. Review and commit the source that will be distributed. Build a fresh Linux
   release and [Debian package](DEBIAN_PACKAGING.md), then verify its checksum,
   packaging tests and installed-app behaviour. Do not rename an older binary.
5. Push the source commit. Create an unused application tag on that exact commit:

   ```bash
   git tag -a v0.6.3 -m "DenucziTV 0.6.3" &&
   git push origin main &&
   git push origin v0.6.3
   ```

6. After QA, create a stable release with the platforms already verified:

   ```bash
   gh release create v0.6.3 \
     dist/denuczitv_0.6.3+1-1_amd64.deb \
     dist/denuczitv_0.6.3+1-1_amd64.deb.sha256 \
     --repo denuczi/DenucziTV \
     --verify-tag \
     --title "DenucziTV 0.6.3" \
     --notes-file docs/releases/v0.6.3.md \
     --latest \
     --prerelease=false
   ```

7. Use the [Windows installer workflow](WINDOWS_PACKAGING.md) with that same tag.
   Download its artifact, test it on Windows, and attach the verified installer
   and checksum to the existing release. Update the description when the new
   platform is available.

When publishing through the website, leave **Set as a pre-release** unchecked
for a stable version and select **Set as the latest release**. A successful build
alone does not establish stability; complete the native installation checks.

## Add a Windows installer to an existing release

Build and test the same application tag, following [WINDOWS_PACKAGING.md](WINDOWS_PACKAGING.md).
The following commands are for 0.6.2, with files downloaded to
`dist/windows-v0.6.2`. Run them from the repository root. The checksum command
uses a subshell so the terminal stays in that root directory:

```bash
(cd dist/windows-v0.6.2 && sha256sum --check DenucziTV-Setup-0.6.2-x64.exe.sha256)
```

Only if those assets are not already published, upload them:

```bash
gh release upload v0.6.2 \
  dist/windows-v0.6.2/DenucziTV-Setup-0.6.2-x64.exe \
  dist/windows-v0.6.2/DenucziTV-Setup-0.6.2-x64.exe.sha256 \
  --repo denuczi/DenucziTV
```

This preserves the Linux assets. Do not use `--clobber` to replace a published
installer. A changed application requires a new application version and tag.
The `.build-info.json` is optional technical provenance, not an installer.

To apply the reviewed English release description from the repository:

```bash
gh release edit v0.6.2 --repo denuczi/DenucziTV --notes-file docs/releases/v0.6.2.md
```

This replaces the complete release description with that file. Review it first
and preserve any additional notes that should remain public.

## Verify the published result

```bash
gh api repos/denuczi/DenucziTV/releases/tags/v0.6.2 \
  --jq '{tag: .tag_name, draft: .draft, prerelease: .prerelease, assets: [.assets[].name]}'
gh release view v0.6.2 --repo denuczi/DenucziTV --web
```

For a published stable release, `draft` and `prerelease` must both be `false`.
Check the exact filenames and verify that downloads are accessible without
signing in. The repository must be public for the unauthenticated update checker.

## Stable update policy

From 0.6.2, the application offers only newer stable releases with compatible
official installer assets. Prereleases and drafts are excluded. Installation
remains manual. Never change a real release flag just to test the modal; use
[the isolated fixtures and preview](UPDATES.md).

Use explicit package prerelease identifiers for future candidates, such as
`0.6.3-rc.1+1`. Plain `0.6.3+1` and stable tag `v0.6.3` compare equal even if one
was previously labelled as a GitHub prerelease. Build numbers do not force an
application update. Keep the installer naming contract in [UPDATES.md](UPDATES.md).

## Documentation after publication

- Update the README download table and installation filenames for both platforms.
- Keep the local release notes consistent with the published description.
- Update the changelog status, packaging examples and actual validation record.
- Retain historical version entries and identify older screenshots accurately.

Documentation-only changes do not require rebuilding or replacing installers.
Before downgrading, review the library migration notes in
[PROTECTED_SINGLE_LINK.md](PROTECTED_SINGLE_LINK.md); older binaries may not read
newer personal-library databases.
