# Slice A0 — `Sendable` conformance for `ArgumentParserToolInfo` V0 types

## Summary

Adds `Sendable` conformance to every public type in
`ArgumentParserToolInfo`. The change is purely additive: V0 types remain
`Codable, Hashable` and acquire `Sendable` alongside. No field changes,
no behavioral changes, no JSON-shape changes.

This unblocks the upcoming `ToolInfoV1` schema (Slice A), whose types
will reuse several V0 enums via `typealias` and need to be `Sendable` to
expose a `Sendable` V1 surface.

## Types updated

In `Sources/ArgumentParserToolInfo/ToolInfo.swift`:

- `ToolInfoHeader`
- `ToolInfoV0`
- `CommandInfoV0`
- `ArgumentInfoV0`
- `ArgumentInfoV0.NameInfoV0`
- `ArgumentInfoV0.NameInfoV0.KindV0`
- `ArgumentInfoV0.KindV0`
- `ArgumentInfoV0.ParsingStrategyV0`
- `ArgumentInfoV0.CompletionKindV0`

All conform trivially: each is a value type whose stored fields are
`String`, `Bool`, `Int`, `[String]`, or other types in this list.

## Tests

`Tests/ArgumentParserToolInfoTests/V0SendableTests.swift` adds a single
async smoke test that constructs a populated `ToolInfoV0` and a
`ToolInfoHeader` and ferries them across an actor-isolated
`Task.detached`. Compilation is the assertion — losing `Sendable`
anywhere in the V0 surface fails the build.

## Verification

- `swift build` — clean.
- `swift test` — 536 tests pass, no regressions.

## Out of scope

- No V0 deprecations.
- No new V0 fields.
- No changes to V0 JSON shape, V0 init signatures, or V0 generation
  logic in `DumpHelpGenerator`.
- No `@unchecked Sendable`. All conformances are checked.

## Risks

- If any consumer was relying on the absence of `Sendable` (e.g.,
  through retroactive `Sendable` conformance of their own), they'll see
  a redundant-conformance warning. Unlikely; flagged for awareness.
- Strict-concurrency warnings elsewhere in the repo may surface once V0
  is `Sendable`. Build is currently clean; if a future change exposes
  one, it's a downstream issue, not a Slice A0 issue.
