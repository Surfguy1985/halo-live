# HALO RC1 — Swift / workflow-backend contract audit

## Verified by source inspection

- `NativeiOS/HaloField/Networking/HaloAPI.swift` currently defaults to a **Base44** URL and uses `/functions/nativeFieldMobile` for native operations.
- `NativeiOS/HaloField/Domain/HaloTemplatePublishing.swift` defines a **proposal model and documented contract**, not a deployed network client.
- The isolated enterprise HTTP adapter exposes `POST /v1/workflow-templates/{templateID}/publish`, only when enabled and supplied with a verified server-side session.
- Swift `HaloWorkflowBlocks.Layout` and backend `validateLayoutV1` both use schema version 1 and the same eight block kinds.
- Swift layout validation is a client-side preview. Backend validation imposes additional restrictions (IDs, title/config lengths, per-kind typed config values, duplicate roles), so Swift-valid drafts **may be rejected** by the server.

## Integration gaps / release blockers

1. **No live bridge**: the Base44 native mobile endpoint is not the enterprise publishing endpoint. Do not repoint `HaloAPI` until a staging service, verified bearer issuer/audience, and membership mapping exist.
2. **No complete API client**: Swift has no implementation for authenticated workflow publishing, conflict recovery, or error decoding from this enterprise backend.
3. **Server authority**: never trust Swift `tenantID`, `industryID`, `actorID`, local role filtering, or local transition decisions as authorization.
4. **Wire contract**: Swift proposal fields `requestID`, `expectedRevision`, and `layout` must be encoded as expected by the backend; `Idempotency-Key` must equal `requestID`. Test actual JSONEncoder output and backend parsing on macOS.
5. **Error contract**: Swift documentation lists response shapes that may differ from current backend errors (e.g. `{error:"REVISION_CONFLICT"}`); establish an explicit versioned error schema.
6. **Offline safety**: no automatic replay of financial, approval, or uncertain external side-effect operations; require revision/idempotency reconciliation and human review where appropriate.
7. **Native verification**: execute Xcode build and XCTest on macOS for the exact RC1 SHA. Linux/Node CI cannot prove Swift compilation or iOS runtime behavior.

## New CI safeguard

`swift-contract-drift.test.mjs` checks schema version, block kinds, Swift field names, proposal fields, and the current separate transport boundary. It is a **source-level drift detector**, not an end-to-end Swift/Node interoperability test.

**Status:** blocked from production integration pending the above evidence. No Base44, Swift runtime, or production endpoint changed.
