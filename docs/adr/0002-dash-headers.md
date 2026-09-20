# 0002 — DASH segment headers decide whether a loopback proxy exists

Status: open, pending spike

## Context

MovieBox DASH manifests are served from CloudFront and every request, manifest and segment alike,
needs `Cookie: CloudFront-Policy=...; CloudFront-Signature=...; CloudFront-Key-Pair-Id=...` plus a
`Referer` and a matching User-Agent. The CDN returns 403 without them.

The Rust reference solves this with a 610-line detached loopback proxy, but only because VLC and
Android intents cannot accept arbitrary request headers. An in-process player has no such limit.

## Decision

Deferred until `tool/spike_dash_headers.dart` runs on Windows, Linux and Android. media_kit ships a
different libmpv build per platform, so the answer is per-platform until proven otherwise.

The spike serves a synthetic manifest whose `SegmentTemplate` points back at the spike's own server
and asserts the probe cookie arrives on segment requests, not just the manifest.

## Consequences

- Pass: `proxy.rs` is never ported.
- Fail: an in-process `HttpServer` on `127.0.0.1:0` is required, with host-scoped manifest
  rewriting. The reference's pure functions and their tests port directly; the security defects do
  not. Headers stay in memory rather than argv, the target host is pinned to an allowlist, and the
  route carries a per-session token.

## Status log

**2026-09-21 — spike written, not yet run.** `tool/spike_dash_headers.dart` is complete and
analyzes clean. It could not be executed on this Windows machine: `flutter build windows` stops at
"Building with plugins requires symlink support", which needs Developer Mode, and the account here
is not an administrator.

Until a verdict exists, the port assumes the proxy is unnecessary and passes headers straight to
`Media(url, httpHeaders: ...)`. That assumption is isolated to one call site, so reversing it means
adding the proxy, not rewriting the player.

Run it with:

```
flutter run -t tool/spike_dash_headers.dart -d windows
flutter run -t tool/spike_dash_headers.dart -d linux
flutter run -t tool/spike_dash_headers.dart -d <android-device>
```

It prints `SPIKE PASS` or `SPIKE FAIL` and shows the same verdict on screen.
