# Microsoft Store distribution (MSIX)

**DenucziTV 0.6.3 has passed Microsoft Store certification and is published.**
The public listing is [DenucziTV on Microsoft Store](https://apps.microsoft.com/detail/9p25pqphwdvr), Store ID `9P25PQPHWDVR` (first publication: November 11, 2026).

## Install from Microsoft Store

On a compatible Windows 10/11 x64 PC, open the listing above, select **Get** or
**Install**, and follow Microsoft Store's prompts. Store availability can vary by
region and account configuration. The Store edition receives its updates through
Microsoft Store rather than DenucziTV's GitHub stable-release updater.

The Store is an additional distribution channel. Users can continue to install
the **standalone Windows EXE** or **Debian DEB** from the
[public download instructions](../README.md#download). Do not assume the Store
edition and standalone EXE edition share settings, secrets, downloads, or local
libraries: MSIX storage virtualization may isolate their application data, and
automatic migration between editions is not implemented for 0.6.3.

## Maintainer reference: original 0.6.3 submission

The build and QA instructions below document the original 0.6.3 Store package.
They do not create a new app version, republish the existing submission, move
`v0.6.3`, or replace the GitHub EXE and Debian packages. Future Store updates
require their own versioned packages and submission/certification cycle.

## Release and version policy

| Item | Value |
| --- | --- |
| Public application version | `0.6.3+1` |
| MSIX package version | `1.6.3.0` |
| Store package file | `DenucziTV-0.6.3-x64-store.msix` |
| QA package file | `DenucziTV-0.6.3-x64-qa.msix` |
| Architecture | x64 |

`1.6.3.0` is Windows package metadata, not a new public release. The public
version stays `0.6.3+1`; the MSIX build does not create a new tag, release, or
version. The fourth component is `0`, the first component is not `0`, and every
component is between `0` and `65535`, as required by Microsoft package-version
rules.

Do not upload the QA package to Partner Center. The Store package is intentionally
unsigned at build time and Microsoft Store re-signs it after submission.

## Partner Center identity

These values must match the reserved product in Partner Center exactly.

| Field | Value |
| --- | --- |
| Product/identity name | `IgnacioSanguina.DenucziTV` |
| Publisher | `CN=055E0D46-1999-438C-9CDB-4069928369ED` |
| Publisher display name | `Ignacio Sanguina` |
| Package family name | `IgnacioSanguina.DenucziTV_kxktqdr75pfwr` |
| Store ID | `9P25PQPHWDVR` |
| Display name | `DenucziTV` |

The repository configuration is in the root `msix_config` block of
`pubspec.yaml`. `identity_name` is the Partner Center **Identity Name**, not the
package family name. The publisher string is quoted because it contains `=`.

## Files

- `.github/workflows/microsoft-store.yml`: manually dispatched Windows build.
- `scripts/package-msix.ps1`: clean build, Store package, QA package, checks.
- `packaging/windows/flutter-toolchain.cmake`: disables the unused JNI bridge.
- `pubspec.yaml`: MSIX identity and package version; `msix` is a dev dependency.
- `docs/privacy.html`: privacy policy for the Store listing and GitHub Pages.

The workflow performs a single checkout of `source_ref` into `source`. The
packaging script, packaging tests, CMake toolchain policy, `pubspec.yaml`, and
application code therefore all come from the same exact revision. The workflow
resolves that checkout to a full SHA, rejects a dirty checkout, re-checks the
worktree after the quality gates, and passes the SHA to the packager, which
compares it with `git rev-parse HEAD` before building.
The source can be a branch, tag, or full commit. The source must contain the
reviewed MSIX configuration and the `msix: ^3.18.0` development dependency; the
workflow does not depend on the existing `v0.6.3` tag containing the new files.
It records the exact source SHA in the build metadata and does not create
releases or modify tags. The workflow uses no repository secrets and has
read-only `contents` permission, so a non-default `source_ref` cannot read secret
values.

## Build from Linux

Commit and push the reviewed packaging files to the default branch first, because
GitHub only offers manually dispatched workflows that exist on the default
branch. Do not recreate or move the application tag.

```bash
gh workflow run microsoft-store.yml \
  --repo denuczi/DenucziTV \
  --ref main \
  -f source_ref=main \
  -f confirm_public_version=0.6.3
```

`source_ref` may be `main`, another branch, or a commit SHA. Use the same commit
that was reviewed. The single checkout is resolved to a full SHA that is recorded
in the build metadata and passed back to the packager for comparison. The
workflow pins Flutter `3.47.9`, runs formatting, analysis, Flutter tests and
packaging tests, then builds Windows once.

List the run and watch it:

```bash
gh run list --repo denuczi/DenucziTV \
  --workflow microsoft-store.yml --event workflow_dispatch --limit 5
gh run watch RUN_ID --repo denuczi/DenucziTV --exit-status
```

Download the two artifacts after success. Replace `SOURCE_SHA` with the SHA from
the run summary or the artifact name:

```bash
gh run download RUN_ID --repo denuczi/DenucziTV \
  --name denuczitv-msix-store-SOURCE_SHA \
  --dir dist/msix-store
gh run download RUN_ID --repo denuczi/DenucziTV \
  --name denuczitv-msix-qa-SOURCE_SHA \
  --dir dist/msix-qa
```

The Store artifact contains only the unsigned Store MSIX, its SHA-256 sidecar,
and build metadata. The QA artifact contains the test-signed MSIX, its SHA-256
sidecar, build metadata, and the public `.cer` certificate. No PFX or private key
is uploaded.

## What the packager does

1. Verifies the source version is still `0.6.3+1`, the MSIX identity matches
   Partner Center, and the package version is `1.6.3.0`.
2. Removes the previous Windows build tree, sets the repository toolchain policy,
   and runs `flutter build windows --release` once with
   `--dart-define=DENUCZI_STORE_BUILD=true`.
3. Rejects a bundle containing `dartjni.dll`, removes PDB symbols, verifies the
   executable is x64 and reports `0.6.3.1`, copies the official x64 VC++ runtime,
   and snapshots the protected application files.
4. Packages the unsigned Store MSIX once with `--store --sign-msix false`
   and checks that the packaging tool did not modify protected application files.
   The MSIX is verified before any copy or signature operation.
5. Copies the Store MSIX byte-for-byte into the separate QA output directory,
   verifies the copy's SHA-256 against the original, and leaves the Store MSIX
   untouched. No second `msix:create` invocation is needed, so both editions
   have identical application contents and manifest before signing.
6. Signs only the QA copy with a temporary self-signed code-signing certificate
   whose subject is exactly `CN=055E0D46-1999-438C-9CDB-4069928369ED`. The
   certificate is created in `Cert:\CurrentUser\My` with a non-exportable private
   key and selected by thumbprint with `signtool sign /fd SHA256 /s My /sha1`.
   No PFX is created and no password is passed to a process.
7. Verifies both packages: size, SHA-256, ZIP contents, PDB and JNI exclusion,
   manifest identity, publisher, architecture, version, languages,
   `runFullTrust`, executable, signature state, and the public certificate
   subject. It also compares the protected bundle files before and after packaging, compares the payload entries of the Store and QA packages (ignoring
   only the signature and package metadata), and checks that both contain the
   exact official VC++ runtime. For the QA signature, it temporarily trusts the
   signing certificate in `LocalMachine\TrustedPeople` on the Windows CI runner,
   then requires `signtool verify /pa /v` to succeed.
8. Deletes the temporary certificate and its private key, removes the temporary
   machine trust entry, and leaves only the public `.cer` certificate.

The QA certificate is created in `Cert:\CurrentUser\My` and removed in a
`finally` block. Its private key is non-exportable and is deleted with the
certificate. The runner temporarily installs its public certificate in
`Cert:\LocalMachine\TrustedPeople` for MSIX signature verification and removes
that exact thumbprint afterward (including on failure). It never adds this
certificate to the **Trusted Root Certification Authorities** store or exports
private-key material. The hosted Windows runner must have administrative rights;
a writable trust store is checked before the expensive Windows compilation.
Only the public `.cer` is exported. Do not add a PFX, password, `.pem`, `.key`,
or `.p12` to the repository or to a workflow artifact.

## Verify the artifacts

From the artifact directory:

```bash
sha256sum --check DenucziTV-0.6.3-x64-store.msix.sha256
sha256sum --check DenucziTV-0.6.3-x64-qa.msix.sha256
```

On Windows, inspect the manifest without installing:

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead((Resolve-Path '.\DenucziTV-0.6.3-x64-store.msix'))
$entry = $zip.GetEntry('AppxManifest.xml')
$reader = [IO.StreamReader]::new($entry.Open())
$reader.ReadToEnd()
$reader.Dispose()
$zip.Dispose()
```

Check that `Identity` has name `IgnacioSanguina.DenucziTV`, version `1.6.3.0`,
architecture `x64`, and the exact publisher. The build-info JSON records the same
values, plus the source commit, sizes, SHA-256, signature status, runtime version,
bundle-integrity flags, payload hash, and the QA public certificate subject and
thumbprint. It also records that QA was signed from the certificate store and
that no private key was exported.

The Store package must have no `AppxSignature.p7x`. The QA package must contain
it and must verify with `signtool verify /pa /v`. Do not treat an untrusted
self-signed QA package as a production signature.

## Install and test the QA package

Use a Windows 10/11 x64 virtual machine or test computer. Do not use a production
user profile for the first installation test. The QA certificate is disposable;
the private key is not distributed.

1. Verify the QA MSIX hash with the sidecar.
2. From an **elevated PowerShell console** on the test machine, import the
   public QA certificate into `LocalMachine\TrustedPeople`. MSIX App Installer
   does not rely on the current user's personal certificate stores.
3. Confirm the certificate subject is exactly the Store publisher.
4. Install with `Add-AppxPackage` and launch DenucziTV from Start.
5. Remove the package and the test certificate when finished.

```powershell
# Elevated PowerShell on a dedicated test computer or VM.
Import-Certificate -FilePath .\DenucziTV-0.6.3-x64-qa.cer `
  -CertStoreLocation Cert:\LocalMachine\TrustedPeople

Get-AuthenticodeSignature .\DenucziTV-0.6.3-x64-qa.msix |
  Format-List Status, StatusMessage, SignerCertificate

Add-AppxPackage -Path .\DenucziTV-0.6.3-x64-qa.msix
Get-AppxPackage IgnacioSanguina.DenucziTV | Select-Object Name, Version, PackageFullName
```

If installation fails, inspect the actual error and App Installer event log.
Do not bypass package-signature checks or import the QA leaf certificate into
`Trusted Root Certification Authorities`.

After QA, remove the package and the **exact** temporary trust entry from the
test machine. Run this in elevated PowerShell, using the certificate thumbprint
from the QA build-info JSON:

```powershell
Get-AppxPackage IgnacioSanguina.DenucziTV | Remove-AppxPackage
$thumbprint = '<THUMBPRINT_FROM_QA_BUILD_INFO>'
Remove-Item -LiteralPath "Cert:\LocalMachine\TrustedPeople\$thumbprint"
```

QA verification uses temporary machine trust. The status recorded during the
build does not mean the QA package is publicly trusted after that entry is
removed; it is for tests only.

Check the Store-managed update message in Settings: it must explain that
Microsoft Store manages updates and must not show a GitHub check button.

### Data and storage checks

The application still uses the same application-support directory and
`denuczi_tv/library.sqlite` file name. No schema or business logic was changed.
MSIX can virtualize `%APPDATA%`/`%LOCALAPPDATA%` writes under
`%LOCALAPPDATA%\Packages\IgnacioSanguina.DenucziTV_kxktqdr75pfwr\...`, so the
physical location must be verified rather than assumed. The Store edition and
the EXE edition may therefore have separate local data; no automatic migration
from an existing EXE installation is implemented in 0.6.3.

On Windows, test all of the following with synthetic data:

- Create favorites, watch history, and playback progress; close and reopen the
  app; verify the same SQLite database is used and `library.sqlite-wal` and
  `library.sqlite-shm`, when present, remain usable.
- Restart Windows and repeat. Confirm no split database or lost writes.
- Add and remove an account; confirm secrets remain in DPAPI-backed secure
  local storage on Windows and are not written to logs or shared preferences.
- Download a file, cancel and resume it, then reopen the download history.
- Switch English/Spanish and light/dark/system themes; restart and verify
  persistence.
- Uninstall and reinstall the QA package; document whether package data was
  preserved or removed. Do not promise migration unless it was tested.

## Windows App Certification Kit (WACK)

WACK is deprecated and no longer maintained. It can still be used as an optional
local pre-submission check on Windows 10/11 x64 after manual QA, but it is not
the Microsoft Store certification decision. Partner Center performs official
certification after submission. The QA certificate must already be trusted if
the package is installed for testing. A local WACK pass does not replace manual
playback, download, and persistence tests.

Use the Windows App Certification Kit application, or the command line:

```powershell
$wack = "${env:ProgramFiles(x86)}\Windows Kits\10\App Certification Kit\appcert.exe"
& $wack reset
& $wack test `
  -appxpackagepath .\DenucziTV-0.6.3-x64-qa.msix `
  -reportoutputpath .\DenucziTV-0.6.3-x64-wack.xml
```

Review the report, including warnings. Save the WACK result with the source SHA
and QA SHA-256. If WACK changes the package, rebuild and rerun all checks; do not
upload a modified QA package as the Store package.

## Partner Center submission checklist

Prepare these outside this repository, then upload the **Store** MSIX:

- Reserved product name and identity matching the table above.
- Store package built from the reviewed commit and still unsigned.
- Privacy policy URL: `https://denuczi.github.io/DenucziTV/privacy.html`.
- Support/contact details confirmed by the maintainer. The current repository
  contact channel is [GitHub Issues](https://github.com/denuczi/DenucziTV/issues);
  confirm whether Partner Center requires a more direct privacy contact before
  submitting the listing.
- Age rating and content-filter questionnaire answers. DenucziTV is a player;
  the questionnaire must describe that users supply their own provider and
  content, and that no IPTV content is included.
- Pricing and availability for the desired markets; reconfirm the intended
  distribution markets for each future submission.
- At least one rights-safe screenshot at the required desktop size, plus the
  Store icon and description.
- A `runFullTrust` justification: DenucziTV is an existing full-trust desktop
  application that uses local media playback, native media libraries, direct
  downloads, local SQLite storage, and DPAPI-backed secure local storage on
  Windows. No
  restricted capability beyond `runFullTrust` is requested.
- Manual QA record for the same package version; include a WACK report if the
  optional local check is executed.
- Confirmation that the Store package contains no PFX, private key, PDB, JNI
  runtime, or provider credentials.

### `runFullTrust` and Store policy

`runFullTrust` is a restricted capability. Microsoft Store requires a written
justification and may review the app for policy compliance. Do not add unrelated
capabilities to make packaging easier. Do not bypass Store review by distributing
the Store package outside the Store, and do not describe the QA package as a
production Store install.

## Versioning and future updates

The public version and the package version serve different purposes:

| Public version | Example MSIX package version |
| --- | --- |
| `0.6.3+1` | `1.6.3.0` |
| Future `0.7.0+1` | `1.7.0.0` |
| Future `0.6.4+1` | `1.6.4.0` |

Only increase the package version for a new Store submission. The first
component must not be `0`, the fourth component must be `0`, and each component
must be between `0` and `65535`. A rebuilt package with the same version is not a
new Store update. Do not reuse a version after a failed or withdrawn submission
without checking Partner Center's current package history.

The public app version shown inside DenucziTV comes from the Windows executable
resource generated from `pubspec.yaml` (`0.6.3+1`), not from the MSIX manifest
version. Keep both values correct.

### Package flights after the first publication

The first 0.6.3 Store submission was published through the standard submission
flow. Package flights are available for subsequent controlled tests because the
product now has a published submission; they were not available for the first
submission. Check Partner Center eligibility and package versioning before
creating a flight. Never distribute QA-signed packages as production installs.

## Updates in the Store edition

The Store build passes `--dart-define=DENUCZI_STORE_BUILD=true`. That compile-time
flag prevents the GitHub release updater from being created. Settings shows the
localized Store-managed update message instead of the GitHub check controls, and
the app does not call the GitHub release API for updates. This avoids duplicate
update paths and unnecessary GitHub release requests.

The EXE and Debian channels keep the existing GitHub updater unchanged. Microsoft
Store handles updates for the Store edition through the Store package pipeline.
Do not offer a GitHub EXE download inside the Store edition.

## Privacy, IP, and provenance

The Store listing needs a public privacy policy and honest data-handling text.
`docs/privacy.html` covers local settings and library data, provider credentials,
direct provider requests, downloads, update checks, and the absence of analytics
or telemetry. The developer does not receive the user's provider credentials or
IPTV content through DenucziTV.

Submit only rights-safe screenshots and artwork:

- Use an authorized demo provider or synthetic catalog data.
- Do not show provider logos, channel names, movie posters, or other copyrighted
  artwork without permission.
- Do not imply that DenucziTV supplies IPTV content or subscriptions.
- Current repository screenshots are below the Store desktop minimum and include
  provider-supplied catalog artwork. They are not Store submission assets.
- Capture new desktop screenshots at least `1366x768` in **PNG** format
  (actual app, no misleading mockups), with a consistent language and theme.
  Verify the current Partner Center requirements before uploading.
- Keep the original app icon and third-party license notices. Record the source
  commit and package SHA-256 with the submission evidence.

The app is MIT-licensed. Third-party dependencies retain their licenses; review
the bundled license notices generated for the Debian package and the dependency
licenses before publication.

## Publication status, verification, and limitations

**Publication status:** the 0.6.3 Store submission passed Microsoft's
certification and was published on November 11, 2026. The public listing is
[available here](https://apps.microsoft.com/detail/9p25pqphwdvr).
Certification does not prove that every provider, playback format, download,
or Windows configuration has been tested. Keep manual QA records for each
package revision and preserve the reviewed source SHA and package checksum.

For **future submissions**, verify a successful packaging workflow, exact
source revision, Store and QA artifact integrity, and all applicable certification
and manual QA requirements. Review the following again:

- Authorized demo content for screenshots and manual QA.
- Privacy and support contact details, rating and market availability.
- Rights-safe screenshots that meet Partner Center requirements.
- Installed-app playback, download, accessibility, and persistence behavior.
- Data location and account migration behavior between Store and standalone EXE:
  no automatic migration is implemented for 0.6.3.

The Store package is distributed by Microsoft Store, not by downloading the
unsigned Store MSIX or the disposable QA-signed MSIX from CI. The QA certificate
must not be installed as a trusted production publisher.

## Official references

- [Microsoft Store app package requirements](https://learn.microsoft.com/windows/apps/publish/publish-your-app/msix/app-package-requirements)
- [Package flights](https://learn.microsoft.com/windows/apps/publish/package-flights)
- [Reserved names and identities](https://learn.microsoft.com/windows/apps/publish/publish-your-app/msix/reserve-your-apps-name)
- [Restricted capabilities](https://learn.microsoft.com/windows/apps/publish/publish-your-app/msix/restricted-capabilities)
- [Windows App Certification Kit](https://learn.microsoft.com/windows/win32/appxpkg/windows-app-certification-kit)
- [MSIX package signing](https://learn.microsoft.com/windows/msix/package/signing-package-overview)
- [Privacy policy requirements](https://learn.microsoft.com/windows/apps/publish/publish-your-app/msix/app-privacy-policy)
