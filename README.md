<div align="center">

<img src="assets/icon.png" alt="Vesper Movies" width="240">

# Vesper Movies

Find, stream and download movies, series and live TV on desktop, phone and TV.

[English](README.md) - [Hindi](README_HI.md)

</div>

## Platforms

- Windows
- Linux
- Android phone and tablet
- Android TV, Fire TV, Google TV

One codebase. The same APK serves both phone and TV.

## Features

- Discover page with a spotlight banner and rows, from TMDB or keyless Cinemeta
- Latest Bollywood, Tamil, Telugu and Malayalam films and Indian shows on Home when a TMDB key is set
- Search real titles from TMDB, with Cinemeta as a fallback
- Built-in player: libmpv on Windows and Linux, ExoPlayer on Android
- Or open any title in VLC, from Settings
- Plays the best stream automatically, with a cloud menu to switch source and a quality menu to
  switch resolution without losing your place
- Every audio and subtitle track listed and switchable during playback
- Subtitle styling: size, colour, outline, background, position, timing offset
- Continue watching with resume position, per episode progress, mark watched
- My List, backup and restore to a file
- Downloads saved as files you can keep, in a Vesper Movies folder
- Live TV from any M3U playlist
- Full D-pad support on TV

## Sources

| Source | What it gives you |
|---|---|
| MovieBox | Films and series, signed DASH streams, subtitles in many languages |
| HDHub4u | Large Indian and dubbed catalogue, fastest new releases including CAM prints |
| VegaMovies | Hindi dubbed Hollywood and web series |
| MoviesDrive | New Indian and Hollywood releases |
| Movies4u | Multi audio films and web series, direct streams |
| HDMovie2 | Instant streams for Indian serials and new films |
| SkyMoviesHD | Early theatrical prints |
| FilmyCab | Early theatrical prints, HDTC and CAM |
| Bollyflix | Bollywood and Hindi dubbed |
| UHDMovies | 4K, HDR and remux releases |
| TopMovies | Broad catalogue up to 4K |
| 4KHDHub | High bitrate releases up to 2160p |
| NF Mirror | Netflix, Prime Video and Hotstar titles with multiple audio tracks |
| Dramachi | Asian drama series |
| CircleFTP, DhakaFlix | BDIX intranet libraries, only reachable on a Bangladeshi ISP |
| Stremio addons | Anything you add yourself, from Settings |

Every source is asked in parallel when you press Play. Streams are labelled with quality, size,
language and release type (WEB-DL, BluRay, HDTC, CAM). Real releases rank above CAM prints, and
Hindi or dual audio ranks first unless you turn that off in Settings.

These sites move to new domains often. Vesper reads a public list of current domains at startup, so
a move does not break the source.

## Known limits

- The two BDIX sources only respond on a Bangladeshi ISP intranet.
- Some Bollyflix and GDFlix links sit behind a Cloudflare check that may block them on some
  networks. Other sources for the same title still play.
- Streaming playlists (HLS and DASH) play but cannot be downloaded. Pick a file download instead.
- VLC on Android cannot receive request headers, so Vesper hands it direct file streams only.

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
| Fullscreen | F | Double-click | - | Always on |
| Exit | Esc | - | Back gesture | Back |

## Install

Download from the [latest release](https://github.com/AroseEditor/Vesper-Movies/releases/latest).

### Windows

Unzip `vesper-movies-windows-x64.zip` and run `vesper_movies.exe`. Nothing else to install.

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

### Android

- `vesper-movies-arm64-v8a.apk` for most devices
- `vesper-movies-armeabi-v7a.apk` for older 32-bit devices

Allow install from unknown sources when prompted.

### Android TV, Fire TV, Google TV

The same `vesper-movies-arm64-v8a.apk`. Sideload with the Downloader app or ADB:

```bash
adb connect <device-ip>:5555
adb install vesper-movies-arm64-v8a.apk
```

## Build

Needs Flutter 3.47 or newer.

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

On Windows, enable Developer Mode first or the build cannot create symlinks:

```
start ms-settings:developers
```

## TMDB key

Optional. Without it the app uses Cinemeta, which needs no key.

The key never lives in the repository. Create an environment named `main` under Settings,
Environments, and add a secret named `TMDB_API_KEY` to it. The release workflow runs its Android,
Windows and Linux jobs in that environment and compiles the key into every build.

For a local build, keep the key in `tmdb.json`, which is gitignored:

```json
{ "TMDB_API_KEY": "your_key_here" }
```

```bash
flutter run -d windows --dart-define-from-file=tmdb.json
flutter build windows --release --dart-define-from-file=tmdb.json
```

A key compiled into a release binary can be extracted from that binary, so use one you do not mind
exposing. TMDB v3 keys are read-only and rate-limited per key.

## Privacy

- No telemetry, no analytics, no crash reporting
- No server run by this project
- History, list and settings stay on your device
- Logs never contain an IP, a search query, a playlist URL or a full request URL
- URLs are logged as scheme and host only
- File paths are logged relative to your home directory

Streaming still means contacting the servers that host the content, and they see your IP the same
way a browser would. Two sources use plain HTTP on a local network by design, and are permitted to
do so only for their own addresses.

## Licence

MIT. See [LICENSE](LICENSE).

## Disclaimer

This project hosts and stores no media. It is a client for publicly reachable streams. Complying
with the law where you live is your responsibility.
