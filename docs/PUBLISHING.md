# Publishing source and releases

Run publishing commands from a normal local terminal with network access and a
writable `.git` directory. Binary packages are GitHub release assets; `dist/` is
ignored by Git and must not be committed.

The current published pre-release is
[v0.6.1](https://github.com/denuczi/DenucziTV/releases/tag/v0.6.1).
Its Linux amd64 installer is `denuczitv_0.6.1+1-1_amd64.deb`.

## Authentication and source updates

Verify access:

```sh
gh auth status
gh repo view denuczi/DenucziTV
```

If authentication fails in your terminal, use
`gh auth login --hostname github.com`. An agent environment may have different
credential access or a read-only `.git` directory even when your terminal works.

Inspect the current branch, remote, and working tree before publishing:

```sh
git status
git remote -v
git diff --check
```

Review and commit only the intended source, documentation, version metadata,
and tests, then push the branch. Keep local configuration, credentials, databases,
and build output excluded. Keep `pubspec.lock` and the native runners tracked.
Do not overwrite remote history to resolve a rejected push.

## Prepare a new version

1. Choose an unused application version and update `pubspec.yaml`, for example
   `0.6.2+1` after 0.6.1. The packager reads this version directly; an environment
   variable selecting a `.deb` for tests does not change the package version.
2. Move the relevant changes into a versioned changelog section. Describe pending
   publication as preparation until the release is published. Preserve earlier
   version entries and do not invent release dates or passing test results.
3. Complete [QA.md](QA.md), including formatting, analysis, and the full test suite.
   `flutter test --concurrency=1` reduces memory pressure on a two-thread machine.
4. Commit the reviewed source and version changes. Build a new release bundle
   from that source and package it using [DEBIAN_PACKAGING.md](DEBIAN_PACKAGING.md).
   Select the matching new archive explicitly for integration checks when `dist/`
   contains multiple versions.
5. Verify the checksum, install or upgrade the package, and check the installed
   app. Record the actual results and any checks that could not be run. Push the
   source commit that corresponds to the application being distributed.

For the published 0.6.1 package, the checksum and installation commands are:

```sh
(cd dist && sha256sum --check denuczitv_0.6.1+1-1_amd64.deb.sha256)
sudo apt install ./dist/denuczitv_0.6.1+1-1_amd64.deb
```

Substitute the new version's exact filenames for subsequent releases. Rebuild
when the application version changes so bundle metadata and Debian control
metadata match. Renaming an older archive does not update its internal version.

## Create the GitHub release

Open [New release](https://github.com/denuczi/DenucziTV/releases/new).

- Create an unused tag matching the application version, such as `v0.6.2`.
- Target the pushed source commit that was tested and built.
- Use an English title and notes explaining user-visible changes, installation,
  platform requirements, and actual validation results.
- Attach the new `.deb` and its matching `.deb.sha256`. The `.build-info.json` is
  optional technical provenance; the dependency log is not needed to install.
- Select **Set as a pre-release** while the version remains a testing candidate.
  A completed package build alone does not establish stability.
- Publish after verifying the tag, target commit, version, and selected files.

For reference, the 0.6.1 release assets are:

```text
denuczitv_0.6.1+1-1_amd64.deb
denuczitv_0.6.1+1-1_amd64.deb.sha256
```

Keep older releases available for history. Library database migrations may
prevent older application versions from opening newer data; see the migration
notes in [PROTECTED_SINGLE_LINK.md](PROTECTED_SINGLE_LINK.md) before downgrading.

## Update documentation after publication

- Point the README's main download and installation links to the published tag.
- Update package filenames and commands in README and Debian packaging examples.
- Change the changelog entry from preparation to pre-release or stable status as
  appropriate. Preserve the limits of the recorded validation.
- Link the current release from the technical guides. Update screenshots only
  when replacement images exist; identify older screenshots accurately.

Documentation-only updates do not require rebuilding the application or replacing
published binaries. Application fixes should receive a new version and release,
with corresponding verification and assets.
