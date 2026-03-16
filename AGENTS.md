# AGENTS

## Scope

These instructions apply to the whole repository unless a deeper `AGENTS.md` overrides them.

## Repository Purpose

This repository is a packaging design workspace with three layers:

- `packages/geo-core`: geometry and data contract layer. It owns template topology, parameter schema, 2D linework output, 3D preview graph output, and content placement validation.
- `apps/frontend`: operator-facing studio. It consumes exported contracts, edits parameters and surface content, and renders 2D/3D previews.
- `apps/backend`: service and integration layer. It may host builds, persist business data, and orchestrate jobs, but it must not become a second geometry engine.

## Architecture Principles

- Geometry rules live in `packages/geo-core` only.
- Frontend and backend consume exported contracts; they do not invent parallel template logic.
- Template metadata, generated 2D output, generated 3D output, and content placement payloads are public interfaces inside this repo. Schema changes must be propagated through all consumers in the same change.
- Prefer one-way dependency flow:
  - `geo-core` defines
  - `frontend` renders
  - `backend` integrates
- Generated files, build output, and copied wasm artifacts are delivery artifacts, not sources of truth.

## Development Order

When a feature touches multiple modules, follow this order:

1. Update `geo-core` data structures and validation.
2. Update wasm exports and serialized payloads.
3. Update frontend types, adapters, and renderers.
4. Update backend passthroughs or persistence only if needed.

## Tooling Policy

- Use Bun as the default JS/TS toolchain.
- Use Zig tooling directly for `geo-core`.
- If Bun needs a platform workaround, document it in the relevant docs instead of silently switching package managers.

## Folder Expectations

- `apps/*`: user-facing or service-facing applications.
- `packages/*`: reusable domain modules and cross-app contracts.
- `packages/geo-core/src/templates`: additive template registry and implementations.
- `apps/frontend/src/lib`: pure helpers, payload adapters, math helpers, and logic worth unit testing.
- `apps/frontend/src/features`: feature-level UI/rendering modules, not generic utilities.

## Cross-Module Rules

- Do not add frontend-only geometry fields to compensate for missing `geo-core` semantics. Fix the contract instead.
- Do not add backend-only template fields that diverge from the frontend/wasm contract unless there is an explicit translation boundary.
- When adding a template, register it through `packages/geo-core/src/templates/mod.zig`.
- When changing preview semantics, document whether the field is:
  - geometry truth
  - rendering hint
  - UI convenience

## Quality Gates

- Zig changes: run the relevant `zig test` or `zig build test`.
- Frontend changes: run `bun run --filter './apps/frontend' test`, `check`, and `build` when practical.
- Wasm boundary changes: rebuild the frontend wasm artifact and verify serialization/deserialization on both sides.
- Any schema change must be validated end-to-end in the same turn.
