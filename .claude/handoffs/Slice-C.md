# Slice C — Typed visitor on V1

## Summary

Rewrites `PropertyMetadata.swift` so each per-property view carries an
`ArgumentInfoV1` node and consumers read everything through that node.
**No forwarding shims.** Old fields (`metadata.name`,
`metadata.abstract`, `metadata.discussion`, `metadata.parentTitle`) are
removed; the standalone `PropertyMetadataNamespace.NameInfo` struct is
gone, replaced by a typealias to `ArgumentInfoV1.NameInfo`.

The per-kind wrapper structs (`OptionValue`, `OptionArray`, etc.) keep
their typed `strategy` and `preferredName` fields — those are more
useful to consumers than the stringly `ParsingStrategy` would be — but
their `metadata` payload now points at the new thin struct.

The `ArgumentInfoV1.init?(argument:)` adapter is lifted out of
`DumpHelpGenerator.swift` into a new internal helper file so the
visitor and the dump generator share one source of truth.

## Files added

- `Sources/ArgumentParser/Utilities/ArgumentInfoV1+Live.swift` — the
  internal `ArgumentInfoV1.init?(argument:)` adapter, plus the
  `internal import ArgumentParserToolInfo` it needs. Used by both the
  V1 dump generator and the typed visitor.

## Files modified

- `Sources/ArgumentParser/Utilities/PropertyMetadata.swift` — wholesale
  rewrite of the public surface:
  - `PropertyMetadataNamespace.NameInfo`: standalone struct removed,
    replaced with `public typealias NameInfo = ArgumentInfoV1.NameInfo`.
  - `PropertyMetadataNamespace.PropertyMetadata`: replaced with
    `{ id: PropertyIdentifier, info: ArgumentInfoV1 }`. Old `name`,
    `abstract`, `discussion`, `parentTitle` fields are removed.
  - `import ArgumentParserToolInfo` added at the top, with the standard
    `#if compiler(>=6.0) public import` / `else import` pattern.
  - The fileprivate `extension NameInfo { init(name: Name) }` is
    removed because the same init now lives in `DumpHelpGenerator.swift`
    as `internal init(name: Name)` on `ArgumentInfoV0.NameInfoV0`. The
    visitor reuses that one.
  - The fileprivate `init(argument:key:)` on `PropertyMetadata` now
    reuses `ArgumentInfoV1.init?(argument:)` from
    `ArgumentInfoV1+Live.swift` and force-unwraps with a precondition
    (the visitor only constructs metadata for `.named`/`.positional`
    arguments, where the V1 init never returns nil).
- `Sources/ArgumentParser/Usage/DumpHelpGenerator.swift`:
  - `ArgumentInfoV1.init?(argument:)` removed (lifted to the new file
    above).
  - Four `fileprivate` helper inits on the V0 enums
    (`KindV0(argument:)`, `ParsingStrategyV0(argument:)`,
    `NameInfoV0(name:)`, `CompletionKindV0(completion:)`) became
    `internal` so the lifted V1 init can call them. They remain hidden
    from external consumers.
- `Sources/ArgumentParser/CMakeLists.txt` — adds
  `ArgumentInfoV1+Live.swift`, `PropertyMetadata.swift`, and
  `ParsableCommand+ToolInfoV1.swift` (the latter was missed in Slice B's
  CMake update). Pre-existing entries unchanged.
- `Sources/ArgumentParserToolInfo/CMakeLists.txt` — adds the five new
  V1 schema files alongside the existing `ToolInfo.swift`.

## Tests modified

`Tests/ArgumentParserUnitTests/PropertyMetadataTests.swift`:

- Existing `testPreferredNamesAndEnumerableFlags` was reading
  `meta.name == "name"` to identify the leaf for `--name`. Updated to
  use `meta.info.preferredName?.name == "name"`, which is the
  correctness-preserving path for V1.
- Added `testPropertyMetadataExposesV1Info` as a small Slice C
  contract test: confirms `metadata.info` is an `ArgumentInfoV1` node
  carrying `kind`, `valueName`, and the visitor-derived `id` /
  `id.path`.
  - The test also documents an existing visitor limitation: per-property
    `sectionTitle` is `nil` for arguments inside an `@OptionGroup(title:
    ...)` because the visitor walks via `Mirror` on a freshly-init'd
    inner type, bypassing the wrapper-init pathway that sets
    `parentTitle` on the underlying argument set. The enclosing group
    node still carries the title (asserted in
    `testGroupWithTitlePropagates`). This was true under the V0
    `metadata.parentTitle` field too — not a regression.

## Verification

- `swift build` — clean.
- `swift test` — 548 tests pass (1 new in this slice), no regressions.

## Consumer migration (deferred)

The handoff document calls for the `swift-workbench-kit` consumer to
migrate to the new API on a parallel `argument-info-v1-migration`
branch and validate the design against this fork's local checkout.
**That step is not done in this slice** because the consumer is in a
separate repository. Expected migration shape:

| Old read | New read |
| --- | --- |
| `metadata.name` | `metadata.info.valueName ?? ""` (or handle nil) |
| `metadata.abstract` | `metadata.info.abstract ?? ""` (or handle nil) |
| `metadata.discussion` | `metadata.info.discussion ?? ""` (or handle nil) |
| `metadata.parentTitle` | `metadata.info.sectionTitle ?? ""` (or handle nil) |
| `PropertyMetadataNamespace.NameInfo.Kind` | `ArgumentInfoV0.NameInfoV0.KindV0` (case shorthands `.long`/`.short`/`.longWithSingleDash` still work) |
| Per-kind wrappers (`ArgumentArray` etc.) | unchanged — same shape, same `strategy`/`preferredName` fields |
| `PropertyMetadataParser` conformance | unchanged |

Audit consumer code for `.isEmpty` checks on the old required-`String`
fields — those become `?.isEmpty ?? true` against the optional V1
fields.

## Out of scope

- `--experimental-dump-help-v1` CLI flag (still deferred from Slice A).
- HelpCommand subcommand-injection FIXME at the top of the V1
  `ToolInfo.init(commandStack:)`.
- Recursive `@OptionGroup` title propagation through
  `Mirror`-traversal — this is a pre-existing visitor limitation, not
  introduced by this slice. See the test comment for context.

## Risks

- **Hidden field-rename damage**: removing `metadata.name` etc. is a
  hard break. The compiler surfaces every removed field as a build
  error in any consumer of `PropertyMetadata`. None remained inside
  this repo after the test update.
- **Empty-string sentinels**: V0 returned `""` for absent
  `parentTitle`/`abstract`/`discussion`; V1 returns `nil`. Consumer
  code with `parentTitle.isEmpty` patterns must shift to
  `parentTitle?.isEmpty ?? true` (or handle the nil case explicitly).
- **`init?(argument:)` lifted to `internal`**: no other completion
  generators in this repo currently invoke it; if a future consumer
  relies on its absence outside the V1 path, the helper file makes the
  collision visible.
