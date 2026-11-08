# DenucziTV

An open-source IPTV player for Linux and Windows, using your own Xtream-compatible provider account.

**[Download the v0.5.3 pre-release](https://github.com/denuczi/DenucziTV/releases/tag/v0.5.3)**

A ready-to-install **Linux `.deb` package** is available in the release's **Assets**
section. You do not need Flutter or a compiler to install it. Choose the `.deb`
file; GitHub's **Source code** ZIP and TAR archives are for developers.

This is a pre-release under active development. DenucziTV does not include
channels, movies, subscriptions, or provider accounts.

## Install

### Linux: Debian package

1. Open the [v0.5.3 release](https://github.com/denuczi/DenucziTV/releases/tag/v0.5.3)
   and expand **Assets**.
2. Download `denuczitv_0.5.3+1-1_amd64.deb` for an x86-64 Linux system. The matching
   `.sha256` file is available to verify the download.
3. Open a terminal in the folder containing the downloaded file and run:

   ```bash
   sudo apt install ./denuczitv_0.5.3+1-1_amd64.deb
   ```

4. Launch **DenucziTV** from your application menu, or run `denuczitv`.

Installation has been checked on **Debian 13 amd64**. Other Debian/Ubuntu versions
must satisfy the package's native library requirements; compatibility with older
releases is not guaranteed. See [Debian package details](docs/DEBIAN_PACKAGING.md)
for dependencies, verification, and removal.

### Windows

The project includes a Windows desktop runner. A Windows installer is not
included in the Linux pre-release described above. Developers can follow the
[Windows build instructions](docs/DEVELOPMENT.md#windows).

## Start using the app

1. Add your provider's server address, username, and password.
2. Browse **Live TV**, **Movies**, or **Series**, depending on your subscription.
3. Use **Settings** to choose the appearance and language, and enable optional
   download, link-copying, or M3U export controls.

Use only services and content you are authorized to access. Exported M3U files
and copied stream URLs can contain account credentials; keep them private.

## Features

- Multiple saved provider accounts with account details and reconnection.
- Live TV, movies, series, category filters, and catalog search.
- Video playback with audio and subtitle selection when the stream supports it.
- Downloads with retry and resume when the provider supports HTTP Range requests.
- Favorites, Continue Watching, and Watch History, stored locally per account.
- Light, dark, and system appearance; English and Spanish interfaces.
- Optional M3U export, stream-link copying, and a configurable User-Agent.

Playback, available tracks, and seeking depend on the provider and native media
libraries. Live TV does not support watch-history resume. Favorites and history
are not synchronized between devices. See [personal-library behavior](docs/PERSONAL_LIBRARY.md).

## Screenshots

### Live TV

![DenucziTV live TV catalog with search and category filters](demo/LiveTV_V0.5.3.png)

### Movie details

![DenucziTV movie details with playback and download actions](demo/movies_V0.5.3.png)

### Series and episodes

![DenucziTV series details with season selection and an episode list](demo/Series_V0.5.3.png)

Screenshots show the interface and provider-supplied catalog information.
DenucziTV does not supply the content shown.

## Documentation and development

| Goal | Guide |
| --- | --- |
| Set up the project, build from source, or understand the architecture | [Development guide](docs/DEVELOPMENT.md) |
| Submit a change or report a bug | [Contributing](CONTRIBUTING.md) |
| Understand favorites, history, and playback progress | [Personal library](docs/PERSONAL_LIBRARY.md) |
| Build or inspect a Debian package | [Debian packaging](docs/DEBIAN_PACKAGING.md) |
| Run release checks | [Quality assurance](docs/QA.md) |
| Report a vulnerability or review credential handling | [Security policy](SECURITY.md) |
| Read the change history | [Changelog](CHANGELOG.md) |

For bugs and feature requests, use [GitHub Issues](https://github.com/denuczi/DenucziTV/issues).
Documentation, issues, and pull requests use standard English; application
translations are maintained separately.

## License

Released under the [MIT License](LICENSE). Third-party dependencies retain their
respective licenses. Created by Ignacio Sanguina.
