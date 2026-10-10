import Foundation

/// Owns the explicit, user-triggered recovery of one uncertain template publish.
/// It never creates a new request ID, advances the expected revision, or retries
/// without a fresh user action.
@MainActor
final class HaloTemplatePublishRecovery: ObservableObject {
    enum RetryReason: Equatable {
        case outcomeStillUnknown
        case serviceUnavailable
        case connectionLost
        case invalidReceipt
        case publishRequestNotFound
        case interrupted
    }

    enum AttentionReason: Equatable {
        case authenticationRequired
        case accessRevoked
        case revisionConflict
        case idempotencyConflict
        case invalidProposal
        case invalidConfiguration
    }

    enum State: Equatable {
        case awaitingUserAction
        case reconciling
        case published(HaloStagingWorkflowClient.Receipt)
        case retryAvailable(RetryReason)
        case needsAttention(AttentionReason)
    }

    typealias ReconcileOperation = (
        _ originalProposal: HaloTemplatePublishing.Proposal,
        _ bearerToken: String
    ) async throws -> HaloStagingWorkflowClient.Receipt

    let uncertainPublish: HaloTemplatePublishing.UncertainPublish
    @Published private(set) var state: State = .awaitingUserAction

    private let bearerToken: () -> String?
    private let reconcileOperation: ReconcileOperation

    convenience init(
        uncertainPublish: HaloTemplatePublishing.UncertainPublish,
        client: HaloStagingWorkflowClient,
        bearerToken: @escaping () -> String?
    ) {
        self.init(
            uncertainPublish: uncertainPublish,
            bearerToken: bearerToken,
            reconcileOperation: { proposal, token in
                try await client.reconcileUncertainPublish(
                    originalProposal: proposal,
                    bearerToken: token
                )
            }
        )
    }

    init(
        uncertainPublish: HaloTemplatePublishing.UncertainPublish,
        bearerToken: @escaping () -> String?,
        reconcileOperation: @escaping ReconcileOperation
    ) {
        self.uncertainPublish = uncertainPublish
        self.bearerToken = bearerToken
        self.reconcileOperation = reconcileOperation
    }

    var canCheckOutcome: Bool {
        switch state {
        case .awaitingUserAction, .retryAvailable, .needsAttention(.authenticationRequired):
            return true
        case .reconciling, .published, .needsAttention:
            return false
        }
    }

    /// Call only in direct response to the recovery button. One invocation makes
    /// at most one request and always supplies the original proposal unchanged.
    func checkPublishOutcome() async {
        guard canCheckOutcome else { return }
        guard let token = bearerToken(), !token.isEmpty else {
            state = .needsAttention(.authenticationRequired)
            return
        }

        state = .reconciling
        do {
            state = .published(try await reconcileOperation(
                uncertainPublish.originalProposal,
                token
            ))
        } catch is CancellationError {
            state = .retryAvailable(.interrupted)
        } catch let failure as HaloStagingWorkflowClient.Failure {
            state = state(for: failure)
        } catch {
            state = .retryAvailable(.connectionLost)
        }
    }

    private func state(for failure: HaloStagingWorkflowClient.Failure) -> State {
        switch failure {
        case .commitOutcomeUnknown:
            return .retryAvailable(.outcomeStillUnknown)
        case .serviceUnavailable, .unexpectedStatus:
            return .retryAvailable(.serviceUnavailable)
        case .invalidResponse:
            return .retryAvailable(.invalidReceipt)
        case .invalidCredentials, .unauthorized:
            return .needsAttention(.authenticationRequired)
        case .forbidden:
            return .needsAttention(.accessRevoked)
        case .revisionConflict:
            return .needsAttention(.revisionConflict)
        case .idempotencyConflict:
            return .needsAttention(.idempotencyConflict)
        case .publishRequestNotFound:
            return .retryAvailable(.publishRequestNotFound)
        case .invalidTemplateID, .invalidSchema:
            return .needsAttention(.invalidProposal)
        case .invalidStagingURL:
            return .needsAttention(.invalidConfiguration)
        }
    }
}
