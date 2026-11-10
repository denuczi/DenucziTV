<p align="center">
  <img src="demo/DenucziTV.webp" alt="DenucziTV" width="100%">
</p>

<h1 align="center">DenucziTV</h1>

<p align="center">
  An open-source IPTV player for <strong>Windows and Linux</strong>.<br>
  Connect your own provider using Xtream Codes or a Protected Single Link.
</p>

<p align="center">
  <a href="#download">Download</a> ·
  <a href="#install">Install</a> ·
  <a href="#features">Features</a> ·
  <a href="#screenshots">Screenshots</a> ·
  <a href="#documentation-and-development">Documentation</a>
</p>

---

<h2 align="center">Download</h2>

<p align="center">
  <strong><a href="https://github.com/denuczi/DenucziTV/releases/tag/v0.6.3">Latest stable release: 0.6.3</a></strong>
</p>

<div align="center">

| Your system | Installer | Checksum |
| :---: | :---: | :---: |
| Windows 10 / 11, x64 | [Download Windows installer](https://github.com/denuczi/DenucziTV/releases/download/v0.6.3/DenucziTV-Setup-0.6.3-x64.exe) | [SHA256](https://github.com/denuczi/DenucziTV/releases/download/v0.6.3/DenucziTV-Setup-0.6.3-x64.exe.sha256) |
| Debian / Ubuntu, x64 | [Download Linux package](https://github.com/denuczi/DenucziTV/releases/download/v0.6.3/denuczitv_0.6.3%2B1-1_amd64.deb) | [SHA256](https://github.com/denuczi/DenucziTV/releases/download/v0.6.3/denuczitv_0.6.3%2B1-1_amd64.deb.sha256) |

</div>

> Microsoft Store distribution is being prepared for 0.6.3 but is not yet
> published. The table above lists the existing direct-download channels. See
> [Microsoft Store MSIX distribution](docs/MICROSOFT_STORE.md) for the packaging
> and certification process.

**You do not need Flutter, Git, or a compiler to install DenucziTV.** Choose the
installer for your system above. The **Source code** ZIP and TAR archives on the
release page are for developers.

DenucziTV does not include channels, movies, subscriptions, or provider accounts.
[View all releases](https://github.com/denuczi/DenucziTV/releases).

## Install

### Windows

1. Download **`DenucziTV-Setup-0.6.3-x64.exe`** using the Windows link above.
2. Run the installer and follow the setup steps.
3. Open **DenucziTV** from the Start menu.

The installer is for 64-bit x64 Windows. It is not digitally signed, so Windows
may display an unknown-publisher or reputation warning.

<details>
<summary>Optional: verify the Windows download</summary>

Download the matching `.exe.sha256` file. In PowerShell, open the folder containing
both files and run:

```powershell
Get-FileHash .\DenucziTV-Setup-0.6.3-x64.exe -Algorithm SHA256
Get-Content .\DenucziTV-Setup-0.6.3-x64.exe.sha256
```

The two SHA256 values must match; letter case does not matter.

</details>

### Linux: Debian / Ubuntu

1. Download **`denuczitv_0.6.3+1-1_amd64.deb`** and its matching `.deb.sha256`
   using the Linux links above.
2. Open a terminal in the folder containing both files and run:

   ```bash
   sha256sum --check denuczitv_0.6.3+1-1_amd64.deb.sha256 &&
   sudo apt install ./denuczitv_0.6.3+1-1_amd64.deb
   ```

3. Launch **DenucziTV** from your application menu, or run `denuczitv`.

The Linux package is built and has been installed on **Debian 13 amd64**. Other
Debian/Ubuntu versions must satisfy its native library requirements; older
systems may not be compatible. See [Debian package details](docs/DEBIAN_PACKAGING.md).

These filenames are for 0.6.3. When installing another version, use that release's
filenames and matching checksum files.

## Start using the app

1. Add a manual **Xtream** account with the provider's server address, username,
   and password, or select **Protected Single Link** and enter a name and the
   provider's permanent link.
2. Browse **Live TV**, **Movies**, or **Series**, depending on your subscription.
3. Use **Settings** to choose the appearance and language, and enable download
   controls. Stream-link copying and M3U export are available for manual Xtream
   accounts. Protected accounts show these settings as unavailable with an
   explanation, while preserving your preferences for manual accounts.

Use only services and content you are authorized to access. Exported M3U files
and copied stream URLs can contain account credentials; keep them private.

## Updates

Open **Settings → Software updates → Check for updates** to check manually.
DenucziTV also checks automatically at startup when a check is due. Only newer
stable releases are offered, and you can choose **Maybe later**.

Download the installer for your system and install it when convenient. The app
does not install updates or restart automatically. Versions before 0.6.2 need a
manual upgrade to obtain the update checker. See [software updates](docs/UPDATES.md).

The Microsoft Store edition receives updates through Microsoft Store and does not
use the GitHub update checker; see [Microsoft Store MSIX distribution](docs/MICROSOFT_STORE.md).

## Features

- Multiple saved Xtream and Protected Single Link accounts.
- Live TV, movies, series, category filters, and catalog search.
- Video playback with audio and subtitle selection when the stream supports it.
- Downloads with reconnection and resume when supported by the provider.
- Favorites, Continue Watching, and Watch History, stored locally per account.
- Stable-release update checks and installer downloads.
- Light, dark, and system appearance; English and Spanish interfaces.
- M3U export and stream-link copying for manual Xtream accounts.
- Automatic credential renewal for Protected Single Link accounts.
- A configurable User-Agent for provider, playback, and download requests.

Playback, available tracks, and seeking depend on the provider and native media
libraries. Live TV does not support watch-history resume. Favorites and history
are not synchronized between devices. Each protected-account renewal starts a
new catalog generation. Earlier history and favorites are retained as unavailable
entries instead of being reassigned by ID or title. See
[personal-library behavior](docs/PERSONAL_LIBRARY.md) and the
[protected connection guide](docs/PROTECTED_SINGLE_LINK.md).

<h2 align="center">Screenshots</h2>

<h3 align="center">Live TV</h3>

<p align="center">
  <a href="demo/LiveTV_V0.5.3.png">
    <img src="demo/LiveTV_V0.5.3.png" alt="DenucziTV live TV catalog with search and category filters" width="100%">
  </a>
</p>

<h3 align="center">Movie details</h3>

<p align="center">
  <a href="demo/movies_V0.5.3.png">
    <img src="demo/movies_V0.5.3.png" alt="DenucziTV movie details with playback and download actions" width="100%">
  </a>
</p>

<h3 align="center">Series and episodes</h3>

<p align="center">
  <a href="demo/Series_V0.5.3.png">
    <img src="demo/Series_V0.5.3.png" alt="DenucziTV series details with season selection and an episode list" width="100%">
  </a>
</p>

Screenshots were captured in 0.5.3 and may differ from the current interface.
They show provider-supplied catalog information; DenucziTV does not supply the
content shown.

## Documentation and development

| Goal | Guide |
| --- | --- |
| Set up the project, build from source, or understand the architecture | [Development guide](docs/DEVELOPMENT.md) |
| Submit a change or report a bug | [Contributing](CONTRIBUTING.md) |
| Understand favorites, history, and playback progress | [Personal library](docs/PERSONAL_LIBRARY.md) |
| Understand protected connections, renewal, expiry, and data migration | [Protected Single Link](docs/PROTECTED_SINGLE_LINK.md) |
| Build or inspect a Debian package | [Debian packaging](docs/DEBIAN_PACKAGING.md) |
| Generate a Windows installer from Linux | [Windows packaging with GitHub Actions](docs/WINDOWS_PACKAGING.md) |
| Prepare, verify, or submit the Microsoft Store MSIX | [Microsoft Store MSIX distribution](docs/MICROSOFT_STORE.md) |
| Understand stable update checks and assisted downloads | [Software updates](docs/UPDATES.md) |
| Run release checks | [Quality assurance](docs/QA.md) |
| Report a vulnerability or review credential handling | [Security policy](SECURITY.md) |
| Read the change history | [Changelog](CHANGELOG.md) |

For bugs and feature requests, use [GitHub Issues](https://github.com/denuczi/DenucziTV/issues).
Documentation, issues, and pull requests use standard English; application
translations are maintained separately.

## License

Released under the [MIT License](LICENSE). Third-party dependencies retain their
respective licenses. Created by Ignacio Sanguina.
