# AGENTS

## Scope

These instructions apply to `apps/frontend`.

## App Purpose

`apps/frontend` is the studio UI for:

- choosing templates exported by wasm
- editing numeric parameters
- editing panel surface content
- rendering 2D dielines
- rendering 3D previews
- surfacing validation and rendering failures in a way operators can understand

It is not the place where packaging topology or fold logic should be redefined.

## Folder Responsibilities

- `src/App.tsx`: top-level orchestration only. Keep it focused on composition, request flow, and high-level state.
- `src/features/*`: feature modules such as template controls, content editor, 2D preview, and 3D preview. Feature files may contain UI-specific logic, but heavy calculation should move out.
- `src/lib/*`: pure helpers, wasm adapters, preview projection math, cache helpers, and logic that should be unit-tested.
- `src/types/*`: payload contracts and frontend-facing API typing.
- `src/components/ui/*`: reusable UI primitives and style-system building blocks.

## Development Style

- Prefer pure helpers in `src/lib` for:
  - payload mapping
  - preview projection
  - text layout
  - data normalization
- Keep React components thin when logic can be tested outside the DOM.
- Local component state is preferred by default. Add a global store only when state genuinely spans multiple distant features and becomes hard to reason about.
- Avoid “shadow contracts” such as custom frontend-only geometry types when the same concept already exists in wasm payloads.

## Rendering Rules

- 2D preview must render directly from `Drawing2DResult`.
- 3D preview must render directly from `Preview3DResult`.
- 2D and 3D content overlays should derive from the same placement semantics. If one renderer needs extra interpretation, isolate it in a helper and keep that interpretation explicit.
- Shared fold/hinge semantics come from exported nodes; do not rebuild them ad hoc in UI code.
- If a renderer approximates curves or text, the approximation belongs in `src/lib`, not inline inside UI components.

## UI Rules

- Use Tailwind CSS and shadcn/ui-style primitives consistently.
- Controls should expose real business semantics:
  - panel dimensions
  - fold angle
  - content position
  - content size
  - rotation
  - font scale
- If a user action can fail due to wasm validation or preview rendering, show the failure in the UI. Do not rely on console output alone.

## Testing Policy

- Pure helpers belong under `src/lib` and should have `bun test` coverage.
- Prefer testing:
  - parameter mapping
  - content patch/merge behavior
  - 2D projection helpers
  - 3D projection helpers
  - text layout helpers
- Avoid brittle screenshot-style tests unless there is a stable rendering harness.
- After structural frontend changes, run:
  - `bun run --filter './apps/frontend' test`
  - `bun run --filter './apps/frontend' check`
  - `bun run --filter './apps/frontend' build`

## Anti-Patterns

- Do not hard-code template registries in frontend code.
- Do not silently swallow rendering errors without surfacing them to the operator.
- Do not duplicate `geo-core` validation logic except for UI affordances; authoritative validation remains in wasm.
