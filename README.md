<div align="center">

<img src="assets/icon.png" alt="Vesper Movies" width="240">

# Vesper Movies

Find, stream and download movies, series and live TV on desktop, phone and TV.

[English](README.md) - [Hindi](README_HI.md) - [Disclaimer](DISCLAIMER.md)

</div>

## What is Vesper Movies

Vesper Movies is a free, open source media player with a Netflix style interface. You browse a
catalogue of films and series, pick a title, and press Play. Vesper asks many public sources at
the same time, picks the best stream for your device and connection, and plays it in its own
player. You can switch source, resolution, audio and subtitles at any time without losing your
place.

It runs on Windows, Linux, Android phones and tablets, and Android TV, Fire TV and Google TV. There
is no account, no sign in, no server and no tracking. Your history and lists stay on your device.

Vesper hosts no media. Read the [disclaimer](DISCLAIMER.md) before use.

## Contents

- [Platforms](#platforms)
- [Features](#features)
- [Install](#install)
- [Getting started](#getting-started)
- [Settings](#settings)
- [Controls](#controls)
- [Sources](#sources)
- [Troubleshooting](#troubleshooting)
- [Privacy](#privacy)
- [Known limits](#known-limits)
- [For developers](#for-developers)
- [Disclaimer](#disclaimer)
- [Licence](#licence)

## Platforms

| Platform | File | Player engine |
|---|---|---|
| Windows 10 and 11 | `vesper-movies-windows-x64-setup.exe` | libmpv |
| Linux x64 | `vesper-movies-linux-x64.tar.gz` | libmpv |
| Android phone and tablet | `vesper-movies-arm64-v8a.apk` | ExoPlayer |
| Older 32 bit Android | `vesper-movies-armeabi-v7a.apk` | ExoPlayer |
| Android TV, Fire TV, Google TV | `vesper-movies-arm64-v8a.apk` | ExoPlayer |

One codebase. The same APK serves both phone and TV.

## Features

### Discover

- Home page with a spotlight banner and rows of trending, popular, new and top rated titles
- Latest Bollywood, Tamil, Telugu and Malayalam films and latest and popular Indian shows
- Genre rows: action, comedy, crime, thriller, sci-fi, drama, horror, romance, animation, documentary
- Categories page with genre filters and Popular, Top rated and Newest sorting
- Search real titles, powered by TMDB with Cinemeta as a fallback
- Details page with synopsis, cast, every season and episode, and More like this

### Watching

- Plays the best available stream automatically, and quietly tries the next one if a stream fails
- Cloud button in the player to switch to any other source for the same title
- Quality menu to switch resolution without losing your place
- Every audio and subtitle track listed and switchable, including external subtitles
- Remembers your audio and subtitle language for every title after
- Subtitle styling: size, colour, outline, background, position and timing
- Skip intro, skip recap, and an automatic next episode countdown
- Hover or drag the seek bar for a thumbnail preview
- True fullscreen with F or F11 on desktop, landscape fullscreen on Android
- Maximum quality setting for slow connections
- Option to open titles in VLC instead of the built in player

### Library

- Continue Watching, with resume position for every film and episode
- Per episode progress bars, and a resume button that picks the right episode
- Mark any film or episode as watched or unwatched
- My List
- Backup and restore your list, history and addons to a single file

### Downloads

- Download any file stream with one tap
- Saved as a normal video file you can keep, move and play anywhere
- Pause, resume and retry

### Other

- Live TV from any M3U playlist
- Stremio compatible addons
- Full remote control and D-pad support on TV
- Update notice when a new version is released

## Install

Download the file for your device from the
[latest release](https://github.com/AroseEditor/Vesper-Movies/releases/latest).

### Windows

1. Download `vesper-movies-windows-x64-setup.exe`.
2. Run it. If Windows SmartScreen appears, choose More info, then Run anyway.
3. Follow the installer. It adds Start Menu and desktop shortcuts.

Updating is the same: run the new installer over the old one. Your history, list, addons and
settings are kept, because they live in your user folder, not the install folder.

To uninstall, use Apps and features in Windows Settings.

### Android phone or tablet

1. Download `vesper-movies-arm64-v8a.apk`. On a very old 32 bit phone use the `armeabi-v7a` file.
2. Open it and allow installing from this source when asked.
3. To update, install the new APK over the old one. Your data is kept.

### Android TV, Fire TV, Google TV

Use the same `vesper-movies-arm64-v8a.apk`. Install it with the Downloader app, or with ADB from a
computer on the same network:

```bash
adb connect <device-ip>:5555
adb install vesper-movies-arm64-v8a.apk
```

### Linux

```bash
tar -xzf vesper-movies-linux-x64.tar.gz
./vesper_movies
```

If libmpv is missing:

```bash
sudo apt install libmpv2 mpv
sudo pacman -S mpv
```

## Getting started

1. **Open the app.** Home loads a spotlight title and rows of films and series. On TV, use the
   remote arrows. On desktop, use the mouse or keyboard.
2. **Pick a title.** The details page shows the synopsis, cast and, for series, every season. Pick
   a season from the dropdown and an episode from the list.
3. **Press Play.** Vesper searches every source at once and starts the best stream. The first
   time can take a few seconds.
4. **Change source or quality.** In the player, the cloud button at the top right lists every
   source found. The Quality button at the bottom lists every resolution. Either one switches
   without losing your place.
5. **Audio and subtitles.** Use the Audio and Subtitles buttons. Your choice is remembered for the
   next title.
6. **Download.** On the details page, open the more menu on a film or an episode and choose
   Download, then pick the stream to save. Files go to a Vesper Movies folder in your Downloads.
7. **Pick up later.** Anything you stop halfway appears first on Home under Continue Watching.

## Settings

| Setting | What it does |
|---|---|
| Play with | Vesper player, or VLC media player if installed |
| Prefer Hindi audio | Ranks Hindi and dual audio streams first |
| Maximum quality | Auto, 1080p, 720p or 480p. Lower values help on slow connections |
| Subtitles | Default size, colour, background and position |
| Stream addons | Add, enable, disable and remove Stremio compatible addons |
| Route playback through encrypted DNS | Looks up servers privately so network level blocks do not stop playback |
| Backup | Save or restore your list, history and addons |
| Updates | Shows your version and checks for a newer release |
| Watch history | Clear Continue Watching and history |

## Controls

| Action | Keyboard | Mouse | Touch | Remote |
|---|---|---|---|---|
| Play / pause | Space, K | Click video | Tap centre | Center |
| Back 10s | Left, J | Drag bar | Double-tap left | Left |
| Forward 10s | Right, L | Drag bar | Double-tap right | Right |
| Jump 60s | Shift + arrows | Wheel over bar | Drag sideways | Hold arrow |
| Volume | Up / Down | Wheel over video | Drag, right half | System |
| Brightness | - | - | Drag, left half | - |
| Subtitles | T | Click icon | Tap icon | Down, then icon |
| Audio track | A | Click icon | Tap icon | Down, then icon |
| Subtitle delay | Z / X | Panel | Panel | Panel |
| Speed | [ / ] | Panel | Long-press for 2x | Panel |
| Next episode | N | Click card | Tap card | Next key |
| Fullscreen | F, F11 | Double-click | Button | Always on |
| Exit | Esc | - | Back gesture | Back |

## Sources

Vesper reads from these public sources. They are independent third party websites, not part of
this project. See the [disclaimer](DISCLAIMER.md).

| Source | Typical content |
|---|---|
| MovieBox | Films and series with subtitles in many languages |
| HDHub4u | Large Indian and dubbed catalogue, fast new releases |
| VegaMovies | Hindi dubbed films and web series |
| MoviesDrive | Indian and international releases |
| Movies4u | Multi audio films and web series |
| HDMovie2 | Streams for Indian serials and new films |
| SkyMoviesHD | Early releases |
| FilmyCab | Early releases |
| Bollyflix | Bollywood and Hindi dubbed |
| UHDMovies | 4K, HDR and high bitrate releases |
| TopMovies | Broad catalogue up to 4K |
| 4KHDHub | High bitrate releases up to 2160p |
| NF Mirror | Titles with multiple audio tracks |
| Dramachi | Asian drama series |
| CircleFTP, DhakaFlix | Local network libraries, only reachable on specific ISPs |
| Stremio addons | Anything you add yourself, from Settings |

### How a stream is chosen

When you press Play, every source is asked in parallel with a time limit, so one slow site cannot
hold up the rest. Each result is labelled with quality, size, language and release type, such as
WEB-DL, BluRay, HDTC or CAM. Streams are then ranked:

1. Anything above your maximum quality goes last.
2. Full releases rank above theatre recordings.
3. Hindi or dual audio ranks first when Prefer Hindi audio is on.
4. On phones, 1080p is preferred over 4K to save data.

Vesper tries the top stream, and if it does not start, moves to the next one automatically.

These sites change domains often. Vesper reads a public list of current domains at startup, so a
move does not break a source.

## Troubleshooting

| Problem | Try this |
|---|---|
| Nothing plays on mobile data but works on Wi-Fi | Your carrier may block some sites. Keep Route playback through encrypted DNS on. If it still fails, set Private DNS on your phone to `dns.google` in Android network settings |
| Playback keeps buffering | Set Maximum quality to 720p, or pick a smaller stream from the cloud menu |
| No sources found | Try again in a minute, since sites go down briefly. Check the title has been released |
| Only CAM quality is available | New theatrical films often appear as CAM first. Better releases appear later |
| VLC does not open | Install VLC. On Windows it must be in the default Program Files location |
| Home is empty | Check your internet connection, then close and reopen the app |
| Download fails | Pick a different stream. Streaming playlists cannot be downloaded, only files |

To report a problem, open an issue on the repository. On Android, attach the output of
`adb logcat -s flutter` from the moment you press Play.

## Privacy

- No telemetry, no analytics, no crash reporting, no advertising IDs
- No account and no server run by this project
- History, lists, addons and settings stay on your device
- Server lookups can go through encrypted DNS so your network does not see which sites you use
- Logs never contain an IP, a search query, a playlist URL or a full request URL
- URLs are logged as scheme and host only, and file paths relative to your home folder

Streaming still means contacting the servers that host the content, and they see your IP the same
way they would in a browser.

## Known limits

- CircleFTP and DhakaFlix only respond on specific Bangladeshi ISP networks.
- Some links sit behind a Cloudflare check that may block them on some networks. Other sources for
  the same title usually still play.
- Streaming playlists (HLS and DASH) play but cannot be downloaded.
- VLC on Android cannot receive request headers, so Vesper only hands it direct file streams.
- Skip intro uses chapter markers when a file has them, and a timed button otherwise.

## For developers

This section explains how the project is put together, for anyone who wants to build it, read the
code, or contribute.

### Tech stack

| Area | Choice |
|---|---|
| Language and UI | Dart and Flutter, one codebase for every platform |
| State | Riverpod 3 |
| Navigation | go_router with a stateful shell, one navigator per tab |
| Desktop playback | media_kit (libmpv) |
| Android playback | Media3 ExoPlayer through a small platform plugin written in Kotlin |
| HTTP | Dio, with a global dart:io override for encrypted DNS |
| HTML parsing | package:html |
| Metadata | TMDB when a key is present, Cinemeta otherwise |
| Storage | JSON files in the app support folder, SharedPreferences for small settings |
| CI | GitHub Actions: analyse, format, test, then build Windows, Linux and Android |

### Repository layout

```
lib/
  main.dart                app start: caches, encrypted DNS, domain list, stream tunnel
  app.dart                 theme and router
  core/                    errors, logging, redaction, disk cache, encrypted DNS, update check
  design/                  colours, type, motion, shared widgets (poster card, rows, menus)
  shell/                   app shell, side rail, bottom dock, input mode detection
  models/                  catalogue items, details, seasons, releases, provider kinds
  metadata/                TMDB and Cinemeta, merged behind MetadataService
  sources/
    content_source.dart    interface for search based sources
    registry.dart          every source, exposed as Riverpod providers
    source_matcher.dart    scores search results against a title and year
    moviebox/ fourkhdhub/ dramachi/ bdix/ addons/ m3u/
    links/
      link_source.dart     interface for id based sources, LinkQuery, shared helpers
      hosts.dart           HostResolver: follows file host chains to a playable URL
      release_tags.dart    parses quality, codec, language, rip and size from names
      site_domains.dart    live domain list with an offline fallback
      web.dart             shared scraping client
      sites/               one file per site
  player/
    playback_engine.dart   PlaybackEngine interface, MpvEngine, ExoEngine
    player_controller.dart player state, preload, errors, track selection
    external_player.dart   VLC hand off
    quality_cap.dart       maximum quality and Hindi preference
  features/
    home/ categories/ search/ details/ player/ downloads/ live_tv/ settings/ splash/
    details/playback_session.dart   gathers, ranks, resolves and switches streams
  storage/                 library, backup and restore
  downloads/               resumable download engine and queue
android/app/src/main/kotlin/com/vespermovies/app/
  MainActivity.kt          registers the ExoPlayer plugin and the VLC intent
  VesperExoPlayer.kt       ExoPlayer, OkHttp with encrypted DNS, disk cache, tracks, cues
installer/vesper.nsi       Windows installer
.github/workflows/         ci.yml and build.yml
test/                      unit tests, plus live probes tagged live
```

### How playback works

```
Details page
  -> launchPlayback
       -> PlaybackSession.start
            -> gatherReleases     every ContentSource, LinkSource and addon in parallel
            -> rankForDevice      quality cap, CAM last, Hindi first, phone preference
            -> resolvePlayback    LinkSource.resolve or ContentSource.resolve
                 -> HostResolver  redirect decoders, HubCloud, GDFlix, Driveleech, gates, HLS players
            -> PlayerController.load
                 -> PlaybackEngine.open   MpvEngine on desktop, ExoEngine on Android
            -> waitUntilPlayable, or try the next release
```

`PlaybackSession` keeps the ranked list, so the cloud menu, the quality menu and the next episode
countdown all reuse it without searching again.

### Two kinds of source

- **ContentSource** is search based. It searches a site by title, and `SourceMatcher` picks the
  best match by title, year and type. Used by MovieBox, 4KHDHub, Dramachi and the BDIX sources.
- **LinkSource** is id based. It receives a `LinkQuery` with the IMDb id, title, year, season and
  episode, and returns releases directly. Most sites expose an IMDb search or can be matched
  strictly by title and year. Listing is fast because nothing is resolved until you press Play.

### The host resolver

Most sites do not link to video files. They link to file hosts and redirect pages. `HostResolver`
follows those chains until it reaches a playable URL:

| Link type | What happens |
|---|---|
| Encoded redirect pages | Decoded (base64, ROT13, base64 twice, JSON) to the next link |
| hubcdn | The `r` parameter is decoded to a direct file |
| HubDrive, HBLinks, link pages | The first HubCloud or GDFlix link is followed |
| HubCloud, V-Cloud | The drive page gives FSL, FSLv2, PixelDrain and other file servers |
| HubCloud file search | The search API is called for the matching file |
| GDFlix, Driveleech, Driveseed | Direct, cloud and instant download servers |
| `?sid=` gates | The landing forms are posted until the drive link appears |
| Streaming players | Page data or packed JavaScript is read for the HLS playlist |

Results are ranked so the most reliable server type is tried first.

### Networking

- A global `HttpOverrides` routes every dart:io connection through `SecureDns`, which races
  encrypted DNS lookups against the system resolver and uses whichever answers first.
- On desktop, libmpv reaches the network through `StreamTunnel`, a local proxy running in its own
  isolate that uses the same encrypted DNS and handles backpressure.
- On Android, ExoPlayer uses OkHttp with DNS over HTTPS directly.
- Metadata and site domains are cached on disk, so the app starts quickly and works with a patchy
  connection.

### Adding a new source

1. Add a value to `ProviderKind` in `lib/models/provider_kind.dart`.
2. Add a default domain to `lib/sources/links/site_domains.dart` if the site moves often.
3. Create `lib/sources/links/sites/<name>_source.dart`:

```dart
class ExampleSource extends LinkSource {
  ExampleSource(super.web);

  @override
  ProviderKind get kind => ProviderKind.example;

  @override
  Future<List<Release>> find(LinkQuery query, {CancelToken? cancel}) async {
    final page = await web.get(
      '${SiteDomains.of('example')}/?s=${Uri.encodeQueryComponent(query.title)}',
      cancel: cancel,
    );
    return [
      for (final anchor in page.document.querySelectorAll('a'))
        if (isHostLink(anchor.attributes['href'] ?? ''))
          release(cleanText(anchor.text), anchor.attributes['href']!, query: query),
    ];
  }
}
```

4. Register it in `lib/sources/links/sites/all_sites.dart`.
5. If the site uses a file host the resolver does not know, add a branch in `HostResolver._resolve`.
6. Run the live probe for just your site:

```bash
flutter test test/link_sources_probe.dart --tags live --dart-define=SITE=example
```

### Building

Needs Flutter 3.47 or newer. On Windows, enable Developer Mode first or the build cannot create
symlinks (`start ms-settings:developers`).

```bash
git clone https://github.com/AroseEditor/Vesper-Movies.git
cd Vesper-Movies
flutter pub get
flutter run -d windows
```

Release builds:

```bash
flutter build apk --release --split-per-abi
flutter build windows --release
flutter build linux --release
```

### TMDB key

Optional. Without it the app uses Cinemeta, which needs no key, and the Indian rows are hidden.

The key never lives in the repository. For releases, create an environment named `main` under the
repository Settings, Environments, and add a secret named `TMDB_API_KEY`. The build workflow runs
every job in that environment, compiles the key into every build, and fails if the key is missing.

For a local build, keep the key in `tmdb.json`, which is gitignored:

```json
{ "TMDB_API_KEY": "your_key_here" }
```

```bash
flutter run -d windows --dart-define-from-file=tmdb.json
```

A key compiled into a binary can be extracted from it, so use one you do not mind exposing. TMDB
v3 keys are read only and rate limited per key.

### Testing

```bash
flutter analyze
dart format --output=none --set-exit-if-changed lib test
flutter test --exclude-tags live
```

Unit tests cover signing, parsing, ranking, tag parsing, title matching, caching, backup and
more. Tests tagged `live` hit real websites. They are for diagnosis, not CI, since sites change.

### Releases

Pushing a tag such as `v0.6.0` runs `build.yml`, which builds the Android APKs, the Windows
installer and the Linux archive, writes release notes from the commit log, and publishes a GitHub
release.

### Conventions

- No comments in code. Names and structure carry the meaning.
- `dart format` with a line length of 100, enforced in CI.
- Small, focused commits in conventional style, such as `fix(player): ...` or `feat(sources): ...`.

## Disclaimer

Vesper Movies hosts, stores and distributes no media. It is a client that plays content from
independent third party websites the authors do not control or endorse. You are responsible for
making sure your use is lawful where you live. The software comes with no warranty.

Read the full [disclaimer](DISCLAIMER.md) before use.

## Licence

MIT. See [LICENSE](LICENSE). The licence covers the source code only, not any third party content.
