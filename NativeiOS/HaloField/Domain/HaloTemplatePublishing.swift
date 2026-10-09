import Foundation

/// A client-side publishing proposal. Authorization and revision checks happen on the server.
enum HaloTemplatePublishing {
    struct Proposal: Codable, Equatable {
        let requestID: UUID
        let expectedRevision: Int
        let layout: HaloWorkflowBlocks.Layout
    }

    enum Failure: Error, Equatable {
        case invalidLayout
        case invalidRevision
        case invalidActor
    }

    static func prepare(
        layout: HaloWorkflowBlocks.Layout,
        expectedRevision: Int,
        actorID: String,
        requestID: UUID
    ) -> Result<Proposal, Failure> {
        guard case .success = HaloWorkflowBlocks.validate(layout) else {
            return .failure(.invalidLayout)
        }
        // JSON numbers in the Node publishing service must be JavaScript-safe integers.
        guard expectedRevision >= 0, expectedRevision < 9_007_199_254_740_991 else {
            return .failure(.invalidRevision)
        }
        guard !actorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.invalidActor)
        }
        return .success(Proposal(requestID: requestID,
                                 expectedRevision: expectedRevision, layout: layout))
    }
}

/// Backend contract, not an implementation of backend security.
/// POST /v1/workflow-templates/{templateID}/publish
/// Header: Idempotency-Key: {requestID}
/// Body: Proposal; backend authenticates actor from session, not client actorID.
/// 200: Published { revision, templateVersion }
/// 409: Conflict { currentRevision }
/// 403: Forbidden
/// 422: InvalidSchema { errors }
/// Server MUST compare revisions atomically, scope tenant by session, verify publish rights,
/// validate block configuration, record immutable audit events and deduplicate requestID.
