import Foundation

/// Persists the exact request before the first publish attempt, then removes it
/// only after a verified receipt or definitive rejection. It never reconciles
/// or retries automatically; recovery remains a separate, explicit user action.
struct HaloTemplatePublishCoordinator {
    enum Outcome: Equatable {
        case published(HaloStagingWorkflowClient.Receipt)
        case recoveryRequired(HaloTemplatePublishing.UncertainPublish)
    }

    typealias PublishOperation = (
        _ proposal: HaloTemplatePublishing.Proposal,
        _ bearerToken: String
    ) async throws -> HaloStagingWorkflowClient.Receipt

    private let recoveryStore: HaloTemplatePublishRecoveryStore
    private let publishOperation: PublishOperation
    private let now: () -> Date

    init(
        client: HaloStagingWorkflowClient,
        recoveryStore: HaloTemplatePublishRecoveryStore,
        now: @escaping () -> Date = Date.init
    ) {
        self.init(
            recoveryStore: recoveryStore,
            now: now,
            publishOperation: { proposal, token in
                try await client.publish(proposal: proposal, bearerToken: token)
            }
        )
    }

    init(
        recoveryStore: HaloTemplatePublishRecoveryStore,
        now: @escaping () -> Date = Date.init,
        publishOperation: @escaping PublishOperation
    ) {
        self.recoveryStore = recoveryStore
        self.publishOperation = publishOperation
        self.now = now
    }

    func publish(
        proposal: HaloTemplatePublishing.Proposal,
        bearerToken: String
    ) async throws -> Outcome {
        let uncertain = HaloTemplatePublishing.UncertainPublish(
            originalProposal: proposal,
            detectedAt: now()
        )
        let isNewRequest = try await recoveryStore.save(uncertain)
        guard isNewRequest else {
            let persisted = try await recoveryStore.records().first { $0.id == uncertain.id }
            return .recoveryRequired(persisted ?? uncertain)
        }

        do {
            let receipt = try await publishOperation(proposal, bearerToken)
            // A stale recovery record is safe: relaunch performs a read-only
            // reconciliation. Never turn a confirmed publish into an error just
            // because local cleanup failed.
            try? await recoveryStore.remove(requestID: uncertain.id)
            return .published(receipt)
        } catch let failure as HaloStagingWorkflowClient.Failure {
            guard shouldPreserveForRecovery(failure) else {
                try? await recoveryStore.remove(requestID: uncertain.id)
                throw failure
            }
            return .recoveryRequired(uncertain)
        } catch {
            // Once transport starts, cancellation or a lost connection cannot
            // prove the server rolled back. Preserve the original request.
            return .recoveryRequired(uncertain)
        }
    }

    func pendingRecoveries() async throws -> [HaloTemplatePublishing.UncertainPublish] {
        try await recoveryStore.records()
    }

    func markConfirmed(_ uncertainPublish: HaloTemplatePublishing.UncertainPublish) async throws {
        try await recoveryStore.remove(requestID: uncertainPublish.id)
    }

    private func shouldPreserveForRecovery(
        _ failure: HaloStagingWorkflowClient.Failure
    ) -> Bool {
        switch failure {
        case .commitOutcomeUnknown, .serviceUnavailable, .invalidResponse:
            return true
        case let .unexpectedStatus(status):
            return status >= 500
        case .invalidStagingURL, .invalidCredentials, .invalidTemplateID,
             .unauthorized, .forbidden, .revisionConflict, .idempotencyConflict,
             .publishRequestNotFound, .invalidSchema:
            return false
        }
    }
}
