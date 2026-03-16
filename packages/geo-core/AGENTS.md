# AGENTS

## Scope

These instructions apply to `packages/geo-core`.

## Package Purpose

`geo-core` is the authoritative domain layer for packaging geometry and exported contracts. It owns:

- geometry primitives
- panel boundary validation
- fold semantics
- template parameter schemas
- template instance generation
- 2D dieline outputs
- 3D preview graph outputs
- content placement validation and clipping metadata
- wasm serialization boundaries

If a concept affects topology, geometry truth, or exported payload semantics, it belongs here first.

## Source Layout

- `src/types.zig`
  - shared primitives and reusable domain structs
  - raw path semantics
  - stricter `Panel` validation
  - fold references
  - content placement carriers
- `src/package.zig`
  - model-level contracts
  - editable linework containers
  - 2D output assembly
  - 3D preview node generation
  - model-specific validation helpers
- `src/templates/schema.zig`
  - template descriptor and parameter schema contracts
- `src/templates/*.zig`
  - one file per template implementation
  - parameterized template construction
  - template-specific panel/fold/linework definitions
- `src/templates/mod.zig`
  - template registry and factory boundary
- `src/main.zig`
  - wasm export interface
  - JSON serialization/deserialization
  - stable app-facing payload boundary

## Development Style

- Keep reusable domain semantics in `types.zig`; keep template-specific numbers and topology in `src/templates/*`.
- `Path2D` can stay permissive, but `Panel` must remain strict and validated.
- Prefer explicit fold and preview semantics over inferred client-side behavior.
- If a field exists only to help rendering, state that clearly in naming or comments.
- Avoid storing the same truth in multiple forms unless there is a clear derived/export reason.

## Template Conventions

- Prefer one file per template.
- Use `const Self = @This();` when it improves namespace clarity for template-local types.
- Every template should expose:
  - a descriptor
  - parameter definitions
  - an instance constructor
  - a path into the registry in `src/templates/mod.zig`
- Templates should expose business-meaningful parameters and stable IDs.
- If a template introduces new semantics needed by clients, update wasm output and frontend handling in the same change.

## Contract Rules

- `main.zig` must serialize stable, intentional payloads.
- Do not leak internal Zig-only implementation details as accidental API.
- When adding fields, define whether they are:
  - required domain truth
  - optional rendering hint
  - convenience metadata
- If content placement validation changes, update tests and frontend expectations in the same turn.

## Testing and Validation

- Add or update tests when changing:
  - panel validation
  - content validation
  - template generation
  - fold traversal
  - preview node generation
  - wasm payload serialization
- Run:
  - `zig test src/package.zig`
  - `zig test src/main.zig`
  - or `zig build test`
- Rebuild the wasm artifact after export behavior changes.
