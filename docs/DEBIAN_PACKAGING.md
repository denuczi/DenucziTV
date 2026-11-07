# Debian packaging

The packaging script builds a standalone Debian binary package from an existing
Flutter Linux **release** bundle. It does not rebuild Flutter, install the package,
change repository visibility, or publish a GitHub release. Run it as a regular
user; root access is unnecessary for packaging.

## Prerequisites

Use Debian or Ubuntu with Python 3.11 or newer and these tools:

```bash
sudo apt install dpkg-dev binutils cmake desktop-file-utils
```

Lintian is optional. If installed, the script also runs it and refuses to publish
an archive when Lintian reports errors:

```bash
sudo apt install lintian
```

First verify and build the application as described in [QA.md](QA.md):

```bash
flutter analyze --fatal-infos --fatal-warnings
flutter test
flutter build linux --release
```

## Create and verify the package

From the repository root:

```bash
bash scripts/package-deb.sh
python3 -m unittest discover -s test/packaging -v
```

For `version: 0.5.3+1`, the default amd64 output is:

```text
dist/denuczitv_0.5.3+1-1_amd64.deb
dist/denuczitv_0.5.3+1-1_amd64.deb.sha256
dist/denuczitv_0.5.3+1-1_amd64.build-info.json
dist/denuczitv_0.5.3+1-1_amd64.dependencies.log
```

The last `-1` is the Debian packaging revision. Increment it when redistributing
a changed package of the same application version:

```bash
bash scripts/package-deb.sh --revision 2
```

Other options are `--bundle /path/to/release/bundle` and `--output-dir /path/to/dist`.
The bundle architecture must match the host (amd64 or arm64); cross-packaging is
not supported. To verify a specific archive when multiple versions exist:

```bash
DENUCZITV_DEB=dist/denuczitv_0.5.3+1-1_amd64.deb \
  python3 -m unittest discover -s test/packaging -v
```

The integration checks compare extracted files against the package checksums,
inspect ownership and permissions, verify desktop integration, resolve relocated
native libraries, confirm that the original bundle is unchanged, and exercise
rejection of a bundle with stale version metadata or a missing playback plugin.
When using `--bundle`, the
original-bundle comparison expects the matching standard repository build path.

## Package contents and safeguards

- The complete Flutter bundle is installed in `/usr/lib/denuczitv`; its `data/`
  and `lib/` directories remain adjacent to the executable.
- `/usr/bin/denuczitv` launches the executable and forwards arguments without
  changing the user's working directory or library environment.
- The desktop entry uses the existing GTK application ID from
  `linux/CMakeLists.txt`. Matching that identity helps desktop environments
  associate the running window with the application launcher. Changing the ID
  requires rebuilding the bundle before packaging.
- Icons are installed under the standard hicolor theme at nine sizes. Desktop
  environments handle icon and desktop caches through their package triggers;
  this package has no root maintainer scripts.
- The MIT license and Flutter's generated third-party notices are included in
  `/usr/share/doc/denuczitv`.
- A private staging directory is cleaned up on success or failure. The original
  bundle is never patched. Absolute build paths in ELF RPATH/RUNPATH entries are
  replaced with relative `$ORIGIN` paths in the staged copy using CMake.
- `dpkg-shlibdeps` inspects **every ELF file**, including plugins and bundled
  SQLite, and derives system package dependencies with minimum ABI versions.
  Missing public dependency metadata is an error. The scan must find libmpv.
  Bundled SQLite is retained; a separate system SQLite dependency is only needed
  if the compiled files actually require one.
- Package ownership is root:root, permissions are normalized, checksums are
  generated, and the completed archive replaces the destination atomically.
- The Flutter version and build number must match `pubspec.yaml`. This check
  detects stale version metadata; it does not detect all source edits. Always
  rebuild after changing application code, assets, or native runners.
- `dist/` is ignored by Git. Publish binary packages as release assets after QA
  rather than committing them to source history.

## Distribution compatibility

The generated dependency list comes from the actual build and the distribution's
package metadata, rather than a handwritten list. This follows
[Debian's shared-library dependency rules](https://www.debian.org/doc/debian-policy/ch-sharedlibs.html)
and the documented behavior of
[dpkg-shlibdeps](https://manpages.debian.org/trixie/dpkg-dev/dpkg-shlibdeps.1.en.html).
Keeping the full release bundle follows the
[Flutter Linux deployment guidance](https://docs.flutter.dev/platform-integration/linux/building).

Building on a recent Debian release does **not** guarantee compatibility with an
older Ubuntu or Debian release. For example, the existing Debian 13 amd64 bundle
requires `libc6 (>= 2.38)` and `libglib2.0-0t64 (>= 2.80.0)`. APT should reject
systems that cannot satisfy these requirements. Do not weaken dependencies to
force installation. Build on the oldest distribution you intend to support and
test on each advertised Debian/Ubuntu version with the required native toolchain.

Some `dpkg-shlibdeps` warnings about unversioned private Flutter libraries or
unused links originate in the upstream bundle. The complete diagnostic output
is retained in the dependencies log. Missing libraries and dependency metadata
remain fatal. Lintian is not installed or downloaded automatically.

For reproducible packaging of the **same bundle**, the script normalizes file
timestamps and gzip metadata, uses single-threaded xz, and sets
`SOURCE_DATE_EPOCH` to the latest Git commit timestamp (or the executable's mtime
when Git history is unavailable). You can set `SOURCE_DATE_EPOCH` explicitly.
Reproducing Flutter compilation itself requires the same SDK, dependencies, and
native build environment; this script does not claim reproducible compilation.
The JSON report records archive and original ELF hashes, package dependencies,
build distribution, and source revision/dirty status.

## Local installation and smoke testing

Inspect the package and simulate installation first:

```bash
dpkg-deb --info dist/denuczitv_0.5.3+1-1_amd64.deb
apt-get --simulate install ./dist/denuczitv_0.5.3+1-1_amd64.deb
(cd dist && sha256sum --check denuczitv_0.5.3+1-1_amd64.deb.sha256)
```

When ready, install through APT so dependencies are resolved:

```bash
sudo apt install ./dist/denuczitv_0.5.3+1-1_amd64.deb
denuczitv
```

Check launch from both the terminal and KDE/GNOME application menu. Verify the
icon, playback, downloads, and saved credentials. Secure storage needs an active
desktop Secret Service; on KDE, check your KWallet configuration. Complete the
remaining [manual QA checks](QA.md) on a real desktop before publishing.

Uninstall with `sudo apt remove denuczitv`. User profile data is preserved; the
package does not delete credentials, history, or downloaded files on removal.
