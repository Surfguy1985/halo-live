import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Executed only by the exact-SHA ephemeral CI signoff job. This compiles the
/// production staging transport and sends real URLSession requests through a
/// locally trusted HTTPS terminator to the isolated publishing backend.
@main
struct StagingHTTPSIntegration {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rawURL = environment["HALO_SWIFT_STAGING_URL"],
              let stagingURL = URL(string: rawURL),
              let bearerToken = environment["HALO_SWIFT_BEARER_TOKEN"],
              let fixturePath = environment["HALO_SWIFT_FIXTURE_PATH"],
              let redirectProbeRequestID = environment["HALO_SWIFT_REDIRECT_PROBE_REQUEST_ID"],
              let redirectProbeUUID = UUID(uuidString: redirectProbeRequestID),
              !bearerToken.isEmpty else {
            throw SignoffFailure.missingConfiguration
        }

        let proposal = try JSONDecoder().decode(
            HaloTemplatePublishing.Proposal.self,
            from: Data(contentsOf: URL(fileURLWithPath: fixturePath))
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let client = try HaloStagingWorkflowClient(
            stagingURL: stagingURL,
            sessionConfiguration: configuration
        )

        let expected = HaloStagingWorkflowClient.Receipt(
            templateID: proposal.layout.templateID,
            revision: proposal.expectedRevision + 1,
            templateVersion: proposal.layout.templateVersion
        )
        guard try await client.publish(proposal: proposal, bearerToken: bearerToken) == expected,
              try await client.publish(proposal: proposal, bearerToken: bearerToken) == expected,
              try await client.reconcileUncertainPublish(
                originalProposal: proposal,
                bearerToken: bearerToken
              ) == expected else {
            throw SignoffFailure.invalidReceipt
        }

        let stale = HaloTemplatePublishing.Proposal(
            requestID: UUID(uuidString: "33333333-2222-3333-4444-555555555555")!,
            expectedRevision: proposal.expectedRevision,
            layout: proposal.layout
        )
        do {
            _ = try await client.publish(proposal: stale, bearerToken: bearerToken)
            throw SignoffFailure.expectedRevisionConflict
        } catch HaloStagingWorkflowClient.Failure.revisionConflict {
            // Expected: the idempotent first request is the only committed revision.
        }

        do {
            _ = try await client.publish(proposal: proposal, bearerToken: "invalid.jwt.signature")
            throw SignoffFailure.expectedUnauthorized
        } catch HaloStagingWorkflowClient.Failure.unauthorized {
            // Expected: the real backend rejected an invalid bearer token over TLS.
        }

        let redirectProbe = HaloTemplatePublishing.Proposal(
            requestID: redirectProbeUUID,
            expectedRevision: proposal.expectedRevision,
            layout: proposal.layout
        )
        do {
            _ = try await client.publish(proposal: redirectProbe, bearerToken: bearerToken)
            throw SignoffFailure.expectedRedirectRefusal
        } catch HaloStagingWorkflowClient.Failure.unexpectedStatus(307) {
            // Expected: the production URLSession delegate returned the source
            // redirect response without contacting the credential-capture origin.
        }

        let output: [String: Any] = [
            "transport": "swift-urlsession-trusted-https",
            "publish": "passed",
            "idempotentReplay": "passed",
            "reconciliation": "passed",
            "authorizationFailure": "passed",
            "revisionConflict": "passed",
            "redirectRefusal": "passed"
        ]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: output))
        FileHandle.standardOutput.write(Data([0x0A]))
    }

    private enum SignoffFailure: Error {
        case missingConfiguration
        case invalidReceipt
        case expectedRevisionConflict
        case expectedUnauthorized
        case expectedRedirectRefusal
    }
}
