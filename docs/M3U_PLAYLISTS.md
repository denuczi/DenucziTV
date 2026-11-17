# Extended M3U playlist accounts (0.6.5)

## Supported sources

An M3U account imports an **IPTV Extended M3U catalog** from a local `.m3u`/`.m3u8` file or an HTTP(S) URL. The app follows at most four HTTP redirects while importing a remote catalog, rejects HTTPS-to-HTTP downgrades, and caps the downloaded file at 16 MiB and the parsed catalog at 100,000 entries. A failed refresh retains the last successfully loaded catalog.

HLS media and master playlists are **playback manifests**, not IPTV catalogs. An IPTV catalog may use `#EXT-X-PLAYLIST-TYPE:VOD` immediately after an `#EXTINF` line as a per-entry movie marker (a convention also used by Kodi IPTV Simple). Other `#EXT-X-*` directives still cause the import to reject the document as an HLS playback manifest. The VOD marker is scoped only to the current `#EXTINF` entry and requires a subsequent playable URL.

M3U accounts support Live TV and Movies only. Series/episodes are not synthesized.

## Catalog example

```m3u
#EXTM3U
#EXTINF:-1 tvg-id="news.example" tvg-name="Example News" tvg-logo="https://example.org/news.png" group-title="News",Example News
https://streams.example.org/news/index.m3u8
#EXTINF:-1 group-title="Terror",Example Film
#EXT-X-PLAYLIST-TYPE:VOD
https://streams.example.org/film.m3u8
#EXTINF:-1 group-title="Cinema",Direct movie
https://streams.example.org/movie.mp4
```

Metadata is optional. A movie is identified only by a direct `.mp4`, `.mkv` or `.avi` media URL (case-insensitive; query parameters are ignored), or by a `#EXT-X-PLAYLIST-TYPE:VOD` marker after that entry's `#EXTINF` line and before its URL. The marker also allows HLS (`.m3u8`) VOD streams to appear under Movies.

`group-title`, `tvg-type`, and channel titles do **not** determine Live TV vs Movies: even a channel called "Movies" in a "Cinema" group remains Live TV without an explicit VOD marker or a supported direct-video extension. Group labels are still preserved for filtering. Series classification is unsupported. Playlist updates may reclassify an entry without changing its stable stream ID; existing account data is not deleted automatically.

## Pipe headers

```m3u
#EXTINF:-1,Protected Channel
https://streams.example.org/live.m3u8|user-agent=Custom%20Agent&referer=https://origin.example/&origin=https://origin.example
#EXTINF:-1,Another Channel
https://streams.example.org/live2.m3u8|origin=https://origin.example|referer=https://origin.example/|user-agent=Custom%20Agent
```

Both `&` and repeated `|` delimiters work, in any header order. Header names are case-insensitive. The only accepted keys are `user-agent`, `referer` (also `referrer`), and `origin`. Values are percent-decoded. Duplicate keys, control characters, malformed URLs, and unexpected header names cause only the affected entry to be skipped. Encode `&` and `|` inside header values to prevent ambiguity.

**When any pipe header is supplied, the native player receives exactly those headers**, not the app-wide User-Agent. When there is no pipe, it receives the existing app headers. Redirect behavior for *media playback* is managed by libmpv; the four-redirect rule applies to **catalog import only**.

## Privacy and compatibility

- Source URLs or local file paths can reveal tokens or usernames. Their raw values are stored in the platform's secure storage. SharedPreferences stores only public account metadata; SQLite stores non-reversible item identifiers, names, and watch activity, not media URLs or pipe headers.
- Playlist sources and stream mappings remain separate from Xtream credentials and Protected Single Link. The protected-account expiry and export restrictions are unchanged.
- The original source file must remain accessible for a saved local account to refresh or reconnect. This version does not duplicate or embed the file in app storage.
- M3U stream **download and export actions are disabled** in this version because the Xtream downloader cannot preserve per-stream HTTP headers and its URL generation is provider-specific. Live TV/movie *playback* remains available.
- Only HTTP(S) stream URLs are accepted. Playback of a specific stream depends on the remote server, codec support, and optional headers; successfully importing a catalog does not guarantee every stream will play.
- The Live TV **HLS (.m3u8) / MPEG-TS (.ts)** format switch is only shown for Xtream accounts, where it changes the generated provider URL. For M3U playlists, the user-provided stream URL and pipe headers are used unchanged, and the format switch is not shown.

## QA and regression checklist

1. Run `flutter gen-l10n`, `dart format`, `flutter analyze --fatal-infos --fatal-warnings`, `flutter test --concurrency=1 test/m3u`, and the complete Flutter test suite.
2. On Debian KDE, import a local file, cancel the file picker, import a remote URL with four redirects, and verify the five-redirect and oversized-file errors.
3. Exercise both pipe syntaxes with a test origin that records the actual `User-Agent`, `Referer`, and `Origin` headers, including segment requests for HLS.
4. Switch between Xtream, protected, and M3U accounts. Verify favorites and history stay isolated and an old account's media cannot be played after changing accounts.
5. Test strict movie classification: MP4/MKV/AVI, explicit per-entry VOD for `.m3u8`, groups named Movies/Cinema containing live channels, consecutive entries without marker leakage, and rejection of genuine HLS segment manifests. Confirm the TS/HLS switch is hidden for M3U but remains visible for Xtream. Test movie playback, Live TV numbers and keyboard navigation, and confirm Series is hidden for M3U accounts. Verify refresh preserves data on network failure.
6. Repeat the native file-picker and playback tests on Windows 10/11 for EXE and Microsoft Store MSIX; Linux tests cannot validate those distributions.

M3U support first shipped with the standalone `v0.6.5` release. Microsoft Store updates use a separate certification and distribution channel.
