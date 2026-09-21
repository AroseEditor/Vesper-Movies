# 0002 — Custom headers reach segment requests, so no loopback proxy

Status: accepted

## Context

MovieBox streams are served from CloudFront and every request, manifest and segment alike, needs
`Cookie: CloudFront-Policy=...; CloudFront-Signature=...; CloudFront-Key-Pair-Id=...` plus a
`Referer` and a matching User-Agent. The CDN returns 403 without them.

The Rust reference solves this with a 610-line detached loopback proxy, but only because VLC and
Android intents cannot accept arbitrary request headers. It rewrites the manifest so segment URLs
point back at itself, then injects the auth headers server side.

An in-process player has no such limitation, provided the player actually applies its configured
headers to child requests and not only to the manifest.

## Decision

The proxy is not ported. Headers go straight to `Media(url, httpHeaders: ...)`.

## Evidence

`tool/spike_dash_headers.dart` stands up a loopback `HttpServer`, serves a playlist whose segment
URLs point back at itself, opens it through media_kit with a probe header and a probe cookie, and
records which requests carried them.

Windows, 2026-09-21, media_kit 1.2.6 on Flutter 3.47.5:

```
verdict: PASS - headers reach segment requests, no loopback proxy needed on windows
manifestCarried: true
segmentCarried: true
segmentTotal: 12
proxyCanBeDeleted: true
```

All twelve segment requests carried both the custom header and the cookie.

## Caveats

The probe serves HLS, not DASH. A synthetic MPD was tried first and crashed libmpv with an access
violation, which was traced to the hand-written manifest rather than to header handling: a minimal
probe that only constructs, opens and disposes a `Player` exits cleanly on the same machine. Both
formats are fetched through the same ffmpeg HTTP layer, which is what carries the headers, so the
result transfers. It is evidence, not proof, for DASH specifically.

Only Windows has been measured. media_kit ships a different libmpv build per platform, so Linux and
Android should be run before release:

```
flutter run -t tool/spike_dash_headers.dart -d linux
flutter run -t tool/spike_dash_headers.dart -d <android-device>
```

The release build writes `spike_result.txt` next to the executable and shows the same verdict on
screen.

## Consequences

- `proxy.rs` and its 610 lines are not ported.
- The assumption lives at one call site. If a platform fails the probe, the fix is to add an
  in-process `HttpServer` for that platform, not to rewrite the player.
- If the proxy is ever needed, the reference's pure functions (`extract_target_url`,
  `extract_host_authority`, `rewrite_dash_manifest`) port directly with their tests. Its security
  defects do not: headers must stay in memory rather than argv, the target host must be pinned to an
  allowlist, and the route needs a per-session token.
