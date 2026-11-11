# Publishing source and releases

This guide is for maintainers. To install DenucziTV, use the
[download and installation instructions](../README.md#download).

Run the commands from the repository root in a normal terminal with network
access and a writable `.git` directory. Installers are release assets: keep
`dist/` out of source commits.

## Current stable release

[Version 0.6.4](https://github.com/denuczi/DenucziTV/releases/tag/v0.6.4)
is published as the latest stable GitHub release. Its assets are:

| Platform | Installer | Checksum |
| --- | --- | --- |
| Debian amd64 | `denuczitv_0.6.4+1-1_amd64.deb` | `denuczitv_0.6.4+1-1_amd64.deb.sha256` |
| Windows x64 | `DenucziTV-Setup-0.6.4-x64.exe` | `DenucziTV-Setup-0.6.4-x64.exe.sha256` |

The immutable tag `v0.6.4` points to commit
`d9078f636435621e176305b7eb19eb24082fde10`.
Do not recreate or move the tag, overwrite released binaries, or re-run
publication commands on this already published release.
Documentation-only changes may be committed to `main` afterward without
changing the application binary or tag.

The [Microsoft Store edition](https://apps.microsoft.com/detail/9p25pqphwdvr)
is a separate channel, currently at version 0.6.3 with package version
`1.6.3.0`. The Store receives updates through Partner Center certification,
not GitHub Releases. See [MICROSOFT_STORE.md](MICROSOFT_STORE.md).

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

## Prepare and publish a future application release

This procedure applies only to a **new, unused** version (for example,
`0.6.5`), not to the already published 0.6.4.

1. Update `pubspec.yaml`, `CHANGELOG.md`, release notes and relevant version
   assertions. Commit the exact source that will be distributed.
2. Run [QA.md](QA.md), Linux packaging checks, and actual desktop installation
   tests. Check GitHub Actions before tagging.
3. Create a new annotated tag on the reviewed commit and push it **once**.
   Never retarget a published tag to include documentation changes.
4. Generate installers from that tag. Check SHA-256 and platform-specific QA
   before announcing binaries.
5. Create the GitHub Release as a draft, attach compatible installers and their
   matching checksums, and review the official English notes.
6. Publish the draft as the latest stable release only when every promised
   asset and required verification is complete.
7. Prepare and submit the Store MSIX independently through Partner Center. Its
   package version, identity, workflow and tests must agree on the new version.

To **inspect** the current published release (read-only):

```bash
gh release view v0.6.4 --repo denuczi/DenucziTV --json tagName,isDraft,isPrerelease,assets --jq '{tag: .tagName, draft: .isDraft, prerelease: .isPrerelease, assets: [.assets[].name]}'
```

For instructions and source-of-truth commands, see
[DEBIAN_PACKAGING.md](DEBIAN_PACKAGING.md) and
[WINDOWS_PACKAGING.md](WINDOWS_PACKAGING.md). Release artifacts belong on the
GitHub Release, never in `dist/` inside Git history.

## Stable update policy

From 0.6.2, the application offers only newer stable releases with compatible
official installer assets. Prereleases and drafts are excluded. Installation
remains manual. Never change a real release flag just to test the modal; use
[the isolated fixtures and preview](UPDATES.md).

Use explicit package prerelease identifiers for future candidates, such as
`0.6.5-rc.1+1`. Plain `0.6.5+1` and stable tag `v0.6.5` compare equal even if one
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
