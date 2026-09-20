# 0001 — Riverpod for state management

Status: accepted

## Context

The Rust reference carries a generation counter per request class, aborts the previous task on
re-dispatch, and re-checks staleness at every arrival site. `src/tui/app/requests.rs` is 1,948
lines and most of it is that bookkeeping.

## Decision

Riverpod 3 with code generation.

A result is bound to the key that produced it. When the query changes the widget watches a
different provider instance, the previous one auto-disposes, `ref.onDispose` fires and Dio cancels
the socket. A stale result is written to a provider nobody is watching, so there is no arrival site
to guard.

## Consequences

- The generation counters are deleted rather than ported.
- Debounce must be added back explicitly, keyed off a debounced query provider.
- `build_runner watch` becomes part of the development loop.
- Dropping codegen later is a mechanical rewrite of provider declarations only.
