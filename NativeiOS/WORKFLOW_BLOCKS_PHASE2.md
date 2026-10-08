# HALO Arrangeable Workflow Blocks — Phase 2

## New code

- `HaloField/Domain/HaloWorkflowBlocks.swift`: Codable schema v1, eight block kinds, deterministic ordering, validation, role-filtered *presentation* and local reorder drafts.
- `HaloFieldTests/HaloWorkflowBlocksTests.swift`: six XCTest cases covering schema compatibility, duplicate identifiers/order, visibility, reorder integrity and JSON round-trip.

## Deliberate safety boundaries

- `visibleBlocks` only filters display. Server must verify permissions for every data read and mutation, even when a block is hidden.
- `required` only declares client presentation; server must validate required evidence, state, and authorization.
- Layout tenant and industry fields are identifiers, not trusted credentials.
- Block configuration is an untrusted string dictionary, not an executable expression language. Future typed configuration schema must validate per block.
- Reordering is a draft only, not a persisted or published template.
- No new production paths, default branches, or Base44 content have been modified.

## Required next build

1. Author backend-owned schema and signed, tenant-scoped template API.
2. Add editor role checks and optimistic concurrency for layout publish.
3. Enforce transition permissions, evidence verification, and immutable audit events server-side.
4. Implement native renderer with accessibility and loading/empty/error states.
5. Run macOS XcodeGen compile, XCTest and backend contract tests before integration.

## Local verification

```sh
cd NativeiOS
xcodegen generate
xcodebuild test -project HaloField.xcodeproj -scheme HaloField -destination 'platform=iOS Simulator,name=iPhone 16'
```

Use an installed simulator if that device name is unavailable.
