# 0003 — ContentSource, not Provider

Status: accepted

## Context

The Rust reference calls a stream scraper a `Provider` and splits it across two traits, `Provider`
and `ReleaseProvider`, because Rust async trait objects are awkward.

## Decision

The Dart interface is `ContentSource`, living under `lib/sources/`, and the two traits are merged
into one.

## Consequences

- "Provider" keeps a single meaning in a Riverpod codebase.
- Dart has no object-safety constraint on async interface methods, so the split bought nothing.
- Variation lives in `SourceCapabilities`. A source that cannot serve a query returns an empty list.
