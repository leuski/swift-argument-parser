# Slice B — Public `toolInfoV1` accessor

## Summary

Adds a public `toolInfoV1` accessor on `ParsableCommand` that returns the
V1 description of the command tree. This is the user-facing surface for
introspecting commands from another module without spawning a subprocess.

The accessor is also the carrier for the V1 generation path that Slice A
deferred from a CLI flag — programmatic access lands first; the
`--experimental-dump-help-v1` CLI flag remains a follow-up.

## Files added

- `Sources/ArgumentParser/Parsable Types/ParsableCommand+ToolInfoV1.swift`
  - `public import ArgumentParserToolInfo` (Swift 6) / `import` (Swift 5)
    so the accessor's return type is visible to consumers.
  - `public static var toolInfoV1: ToolInfoV1` on `ParsableCommand`.
  - Carries a `// TODO(naming):` for proposal-review bikeshed.

## Files modified

None. The decision to put the new file in `Sources/ArgumentParser/Parsable Types/`
keeps the change scoped to a single new file; existing import sites
remain on their `internal import` for V0.

## Tests added

`Tests/ArgumentParserEndToEndTests/ToolInfoV1AccessorTests.swift`. This
test target imports `ArgumentParser` *without* `@testable`, so it
exercises the public surface that downstream packages will see. Three
tests:

- `toolInfoV1` returns a value with `serializationVersion == 1` and
  the expected command name.
- The accessor preserves declaration order at the public surface
  (regression check coupled to Slice A's tree walk).
- The result round-trips through JSON via `JSONEncoder` /
  `JSONDecoder`.

## Verification

- `swift build` — clean.
- `swift test` — 547 tests pass (3 new), no regressions.
- External-consumer surface verified: an end-to-end test target with
  plain `import ArgumentParser` reaches `Command.toolInfoV1` and
  `ToolInfoV1` without `@testable` access.

## Out of scope

- `--experimental-dump-help-v1` CLI flag (still deferred).
- `Slice C` typed-visitor rewrite of `PropertyMetadata.swift`.

## Risks

- `public import ArgumentParserToolInfo` re-exports V1 types via
  `ArgumentParser`. That's intentional — the accessor must be usable
  without a separate `import ArgumentParserToolInfo` — but consumers
  that prefer fully-qualified names already get them by importing the
  tool-info module directly. No conflict observed.
- Package manifest tools-version is 5.7. The Swift 6 `public import`
  syntax is gated behind `#if compiler(>=6.0)`; older toolchains take
  the plain-`import` branch which has implicit re-export visibility.
