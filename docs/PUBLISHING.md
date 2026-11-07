# Publishing the initial source repository

These instructions are for the maintainer publishing the initial source tree to
`denuczi/DenucziTV`. Run them from a normal local terminal with network access and
a writable `.git` directory. They do not require a release build.

## Authentication and remote repository

Verify access before changing the remote:

```bash
gh auth status
gh repo view denuczi/DenucziTV
```

If authentication fails, run `gh auth login --hostname github.com`. If the
repository does not exist, create it without adding a remote README or license:

```bash
gh repo create denuczi/DenucziTV --public --description "Open-source IPTV player for Windows and Linux built with Flutter."
```

For an existing repository, verify that its visibility is public in GitHub's
repository settings. Enable Issues to track bugs and feature requests.

## Initial commit and push

For this source directory, which has no initialized Git history:

```bash
git init -b main
git add .
git diff --cached --stat
git diff --cached --check
git commit -m "Initial open-source version of DenucziTV"
git remote add origin https://github.com/denuczi/DenucziTV.git
git push -u origin main
```

Review the staged files before committing. Build output, SDK caches, local
configuration, credentials, and generated localization should be excluded by
`.gitignore`. Keep `pubspec.lock` and the native platform runners tracked.

If the remote already has commits, fetch and inspect them before integrating the
source. Do not force-push over existing history. If `origin` already exists,
inspect `git remote -v` rather than adding it again.

## After publication

- Confirm the repository is public and the MIT license is detected.
- Confirm that Issues and the issue templates are available.
- Inspect the first Flutter Desktop CI run and address failures before releasing.
- Use branches and pull requests for subsequent changes, and update the
  Unreleased section of `CHANGELOG.md`.
- Follow [QA.md](QA.md) before publishing a versioned binary release.
