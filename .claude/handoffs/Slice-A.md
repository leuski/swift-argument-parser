# Slice A — `ToolInfoV1` schema and generation

## Summary

Adds the V1 schema and a V1 generation path. V1 mirrors V0 with one
substantive deviation — argument metadata becomes an ordered tree
(`CommandChildV1`) instead of a flat list — and reuses V0 enums via
typealias to avoid duplication.

The CLI flag wiring (`--experimental-dump-help-v1`) is **deferred to
Slice B**. V1 output is reachable today through
`DumpHelpGeneratorV1(commandStack:).rendered()` and through V1's
test-driven init path. Slice B's public `toolInfoV1` accessor is the
intended user-facing surface.

This deviation from the original Slice A spec was a deliberate
file-touch minimization: shipping the flag would require modifying
~6 existing files (`HelpGenerator`, `CommandParser`, `Errors`,
`MessageInfo`, `ParsableArguments`, plus the generator). With the flag
deferred, Slice A modifies only one existing file.

## Files added

In `Sources/ArgumentParserToolInfo/`:

- `ToolInfoV1.swift` — top-level wrapper, `serializationVersion = 1`.
- `CommandInfoV1.swift` — command metadata, ordered `children` tree,
  recursive subcommands.
- `CommandChildV1.swift` — `enum CommandChildV1 { case argument | group }`
  with custom `Codable` using single-key wrapper form
  (`{"argument": {...}}` / `{"group": {...}}`).
- `ArgumentGroupInfoV1.swift` — `{ title, children: [CommandChildV1]? }`,
  recursive via the enum.
- `ArgumentInfoV1.swift` — per-property metadata, with typealiases for
  `Kind`, `NameInfo`, `ParsingStrategy`, `CompletionKind` pointing at
  the V0 enums (Slice A0 made those `Sendable`).

## Files modified

`Sources/ArgumentParser/Usage/DumpHelpGenerator.swift`:

- Adds `internal struct DumpHelpGeneratorV1` paralleling
  `DumpHelpGenerator`. The V0 generator is unchanged.
- Adds V1 init extensions: `ToolInfoV1.init(commandStack:)`,
  `CommandInfoV1.init(commandStack:)`,
  `ArgumentInfoV1.init?(argument:)`, plus a fileprivate
  `CommandChildV1.children(forArguments:)` helper that walks the
  `ArgumentSet` in declaration order and groups consecutive arguments
  sharing a `parentTitle` into `.group(...)` children.

## Tests added

- `Tests/ArgumentParserToolInfoTests/ToolInfoV1CodableTests.swift` —
  - `ToolInfoV1` JSON round-trip (encode → decode → equality).
  - `CommandChildV1` `.argument` wire format: payload sits under an
    `argument` wrapper key; round-trips.
  - `CommandChildV1` `.group` wire format: payload sits under a
    `group` wrapper key; round-trips.
  - `ToolInfoHeader` correctly identifies `serializationVersion = 1`
    on a V1 payload and `= 0` on a V0 payload.
- `Tests/ArgumentParserUnitTests/DumpHelpGenerationV1Tests.swift` —
  - **Killer test**: a command with interleaved `@Option` /
    `@OptionGroup` / `@Argument` / `@OptionGroup` / `@Option`
    declarations emits its `children` in source-declaration order,
    with each `@OptionGroup` collapsed into a `.group(...)` child.
  - `allValueDescriptions` decoupling: an `ExpressibleByArgument` enum
    populates `allValueDescriptions` independently of `discussion`.
  - V0 regression sniff: `DumpHelpGenerator` (V0) still produces a
    payload whose header reports `serializationVersion = 0` and whose
    command name decodes correctly.

## Verification

- `swift build` — clean.
- `swift test` — 544 tests pass (8 new), no regressions.

## Schema deviations from V0

| Field | V0 | V1 | Why |
| --- | --- | --- | --- |
| arguments tree | `arguments: [ArgumentInfoV0]?` (flat) | `children: [CommandChildV1]?` (ordered enum-tagged tree) | Preserves source-declaration order across interleaved arguments and option groups. |
| `allValueDescriptions` independence | Already separate as a field, but the legacy help text fused values into discussion | Strictly separate at the schema level with no fusion | Lets consumers render enumerated values as a distinct UI block. |
| `Sendable` | (added in A0) | inherits from typealiased V0 enums | Required so the V1 surface can be `Sendable` end-to-end. |

Everything else is field-for-field identical, by design — V1 is a
tree-shape refinement, not a redesign.

## Open questions / TODOs left in code

- `// TODO(wire-format)`: tagged-union with a non-`kind` discriminator
  vs. the chosen wrapper form. Wrapper form was chosen because the
  natural discriminator name `kind` collides with `ArgumentInfoV1.kind`.
- HelpCommand subcommand injection mirrors V0's existing FIXME and is
  not addressed in this slice.
- Nested `@OptionGroup` titles are not preserved as a tree of groups in
  this slice. The current `parentTitle` infrastructure flattens nested
  groups to the innermost title. The schema supports recursion; the
  generator does not yet exercise it. Captured for follow-up.

## Out of scope

- `--experimental-dump-help-v1` CLI flag (deferred to Slice B).
- `ParsableCommand.toolInfoV1` public accessor (Slice B).
- Any V0 changes beyond Slice A0's additive `Sendable`.
- `PropertyMetadata.swift` rewrite (Slice C).
- Consumer migration (post-Slice C).

## Risks

- The declaration-order walk depends on `Mirror`'s iteration order for
  `ParsableArguments`, which is documented to be stable on Apple
  platforms but not formally guaranteed across all toolchains. If a
  Linux build surfaces ordering drift, the walk needs to derive order
  from `InputKey.path` instead. No regressions observed locally.
- The `parentTitle`-based grouping only flattens single-level nesting.
  Consumers expecting recursive group trees today will see a flat list.
  The schema is forward-compatible with deeper nesting; current
  generation logic just doesn't produce it.
