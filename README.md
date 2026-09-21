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
- Search across every enabled source at once
- Built-in player using libmpv
- Every audio, video and subtitle track listed and switchable during playback
- Subtitle styling: size, colour, outline, background, position, timing offset
- Continue watching with resume position
- My List
- Downloads with pause and resume
- Live TV from any M3U playlist
- Full D-pad support on TV

## Sources

| Source | What it gives you |
|---|---|
| MovieBox | Films and series, signed DASH streams, subtitles in many languages |
| 4KHDHub | High bitrate releases up to 2160p |
| Dramachi | Asian drama series |
| CircleFTP | BDIX intranet library, only reachable on a Bangladeshi ISP |
| DhakaFlix | BDIX intranet library, only reachable on a Bangladeshi ISP |
| Stremio addons | Anything you add yourself, from Settings |

Search fans out across all of them at once. A source that is unreachable shows as a dimmed chip
rather than an error, so the results that did arrive still appear.

Add Stremio addons from Settings, reachable from the side rail on desktop and TV or from the
Downloads screen on a phone. Any addon that serves the standard stream resource works.

## Known limits

- The two BDIX sources only respond on a Bangladeshi ISP intranet. Off that network they time out,
  which is expected rather than broken.
- Some 4KHDHub releases point at a redirector page rather than a direct file. Those are labelled
  `(redirect)` and sorted below the direct ones, which play immediately.
- Downloads save direct files. Adaptive streams (DASH and HLS) are streamed but not yet saved.
- The DASH header probe has only been run on Windows, not Linux or Android.

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

The key never lives in the repository. Add it once as a GitHub Actions secret named
`TMDB_API_KEY` under Settings, Secrets and variables, Actions. The release workflow reads it from
there and compiles it into the Windows build only. Android and Linux ship keyless and fall back to
Cinemeta, so a widely sideloaded APK carries nothing to extract.

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
