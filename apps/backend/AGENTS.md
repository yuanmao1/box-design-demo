# AGENTS

## Scope

These instructions apply to `apps/backend`.

## App Purpose

`apps/backend` is the integration layer for business workflows. Its likely responsibilities include:

- serving the frontend build
- auth and user/session integration
- persistence of saved designs and assets
- template catalog management
- export job orchestration
- future API boundaries for external systems

It must not become a second source of packaging geometry truth.

## Folder and Module Intent

- Route handlers should be explicit, typed, and narrow in responsibility.
- Service modules should orchestrate persistence, auth, file handling, or external APIs.
- Any payload mirrored from wasm/frontend should be documented as either:
  - pass-through contract
  - cached contract
  - translated business contract

## Development Rules

- Geometry generation stays in `packages/geo-core`.
- If backend needs preview or template data, it should call or cache exported contracts instead of re-implementing fold logic.
- If a backend endpoint introduces a translated schema, document the translation boundary and why it exists.
- Keep handlers small and push reusable logic into service modules.

## API Rules

- Prefer typed request/response boundaries.
- Avoid casual shape drift between backend payloads and frontend adapters.
- If an endpoint is effectively a proxy to wasm/template generation, preserve field names unless there is a strong business reason not to.

## Validation

- Verify route payloads still match the frontend integration expectations.
- If backend starts invoking wasm generation directly, document ownership and failure semantics clearly.
- Add tests for business logic and serialization boundaries when the backend becomes active enough to warrant them.
