import Foundation
import SwiftData

@MainActor
final class FieldSyncController: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var lastError: String?
    @Published private(set) var attentionCount = 0

    private let api: HaloAPI
    private let queue: OfflineQueue

    init(api: HaloAPI = .shared) {
        self.api = api
        self.queue = OfflineQueue.shared
    }

    func refreshPendingCount(context: ModelContext, activationToken: String?) {
        let counts = queue.counts(in: context, activationToken: activationToken)
        pendingCount = counts.pending
        attentionCount = counts.attention
    }

    func flush(context: ModelContext, activationToken: String?) async {
        guard let activationToken, !activationToken.isEmpty, !isSyncing else {
            refreshPendingCount(context: context, activationToken: activationToken)
            return
        }

        isSyncing = true
        lastError = nil
        defer {
            isSyncing = false
            refreshPendingCount(context: context, activationToken: activationToken)
        }

        let actions: [PendingFieldAction]
        do {
            actions = try queue.ready(in: context, activationToken: activationToken)
        } catch {
            lastError = error.localizedDescription
            return
        }

        for action in actions {
            do {
                try await sync(action, activationToken: activationToken)
                queue.remove(action, context: context)
            } catch {
                let message = error.localizedDescription
                if let apiError = error as? HaloAPIError,
                   case let .http(status, _) = apiError,
                   status >= 400, status < 500,
                   status != 401, status != 408, status != 429 {
                    queue.markPermanentFailure(action, error: message, context: context)
                    lastError = message
                    continue
                }

                queue.markRetry(action, error: message, context: context)
                lastError = message

                // Temporary transport/auth failure: preserve ordering until the
                // dependency can safely replay.
                break
            }
        }
    }

    private func sync(_ action: PendingFieldAction, activationToken: String) async throws {
        guard let kind = PendingActionKind(rawValue: action.kind) else {
            throw HaloAPIError.malformedPayload
        }

        guard
            let raw = try JSONSerialization.jsonObject(with: action.payload) as? [String: Any]
        else { throw HaloAPIError.malformedPayload }

        switch kind {
        case .workflowState, .taskToggle:
            try await api.sendFieldAction(
                id: action.id,
                jobID: action.jobID,
                kind: kind.rawValue,
                payload: raw,
                activationToken: activationToken
            )

        case .turnHandoff:
            guard
                let summary = raw["summary"] as? String,
                let detail = raw["detail"] as? String,
                let urgency = raw["urgency"] as? String,
                let materialEstimate = raw["materialEstimate"] as? String
            else { throw HaloAPIError.malformedPayload }

            try await api.createTurnHandoff(
                handoffID: action.id,
                sourceJobID: action.jobID,
                summary: summary,
                detail: detail,
                urgency: urgency,
                materialEstimate: materialEstimate,
                activationToken: activationToken
            )

        case .proofCaptured:
            guard
                let imagePath = raw["imagePath"] as? String,
                let metadataPath = raw["metadataPath"] as? String
            else { throw HaloAPIError.malformedPayload }

            let imageURL = URL(fileURLWithPath: imagePath)
            let metadataURL = URL(fileURLWithPath: metadataPath)
            let bytes = try Data(contentsOf: imageURL)
            let metadata = try JSONDecoder().decode(
                ProofMetadata.self,
                from: Data(contentsOf: metadataURL)
            )

            try await api.uploadProof(
                metadata: metadata,
                bytes: bytes,
                activationToken: activationToken
            )
        }
    }
}
