import Foundation
import SwiftData

@MainActor
final class FieldSyncController: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var lastError: String?

    private let api: HaloAPI
    private let queue: OfflineQueue

    init(api: HaloAPI = .shared, queue: OfflineQueue = .shared) {
        self.api = api
        self.queue = queue
    }

    func refreshPendingCount(context: ModelContext, activationToken: String?) {
        pendingCount = queue.count(in: context, activationToken: activationToken)
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
                queue.markRetry(action, error: error.localizedDescription, context: context)
                lastError = error.localizedDescription

                // Preserve ordering. Later actions can depend on earlier field state.
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

            let upload = try await api.requestProofUpload(
                jobID: action.jobID,
                size: bytes.count,
                activationToken: activationToken
            )
            try await api.uploadProofBytes(bytes, to: upload.uploadURL)
            try await api.registerProof(
                metadata: metadata,
                objectPath: upload.objectPath,
                activationToken: activationToken
            )
        }
    }
}
