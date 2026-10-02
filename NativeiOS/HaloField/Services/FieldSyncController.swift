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
            await api.reportHealth(category: "offline_queue", message: "HALO could not read the pending offline queue: \(error.localizedDescription)", severity: "high", source: "FieldSyncController", activationToken: activationToken)
            return
        }

        for action in actions {
            do {
                try await sync(action, activationToken: activationToken)
                queue.remove(action, context: context)
            } catch {
                let message = error.localizedDescription

                // The live Unit record is authoritative. If an offline action refers
                // to a task/schema state that no longer exists, or a speculative
                // workflow advance is rejected by current server gates, do not trap
                // the iPhone in a permanent red "sync failed" state. Drop only these
                // known superseded actions and let the next live refresh repaint UI.
                if shouldDiscardSuperseded(action: action, error: error, message: message) {
                    queue.remove(action, context: context)
                    lastError = nil
                    await api.reportHealth(
                        category: "offline_queue",
                        message: "Discarded superseded queued \(action.kind) action after server reconciliation: \(message)",
                        source: "FieldSyncController",
                        jobID: action.jobID.isEmpty ? nil : action.jobID,
                        activationToken: activationToken
                    )
                    continue
                }

                if let apiError = error as? HaloAPIError,
                   case let .http(status, _) = apiError,
                   status >= 400, status < 500,
                   status != 401, status != 408, status != 429 {
                    queue.markPermanentFailure(action, error: message, context: context)
                    lastError = message
                    await api.reportHealth(category: "offline_queue", message: "A queued \(action.kind) action requires attention: \(message)", severity: "high", source: "FieldSyncController", jobID: action.jobID.isEmpty ? nil : action.jobID, activationToken: activationToken)
                    continue
                }

                queue.markRetry(action, error: message, context: context)
                lastError = message
                await api.reportHealth(category: "offline_queue", message: "Queued \(action.kind) replay failed and will retry: \(message)", source: "FieldSyncController", jobID: action.jobID.isEmpty ? nil : action.jobID, activationToken: activationToken)

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
            let bytes = try await Self.readFileData(imageURL)
            let metadataData = try await Self.readFileData(metadataURL)
            let metadata = try JSONDecoder().decode(
                ProofMetadata.self,
                from: metadataData
            )

            try await api.uploadProof(
                metadata: metadata,
                bytes: bytes,
                activationToken: activationToken
            )

            try? FileManager.default.removeItem(at: imageURL)
            try? FileManager.default.removeItem(at: metadataURL)

        case .reworkToggle:
            guard
                let indexText = raw["index"] as? String,
                let index = Int(indexText),
                let checkedText = raw["checked"] as? String
            else { throw HaloAPIError.malformedPayload }
            try await api.toggleRework(
                jobID: action.jobID,
                index: index,
                checked: checkedText == "true",
                activationToken: activationToken
            )

        case .messageSend:
            let text = raw["text"] as? String ?? ""
            let channel = raw["channel"] as? String
            let attachmentPath = raw["attachmentPath"] as? String
            let attachmentData: Data?
            if let attachmentPath {
                attachmentData = try await Self.readFileData(URL(fileURLWithPath: attachmentPath))
            } else {
                attachmentData = nil
            }
            try await api.sendMessage(
                text: text,
                jobID: action.jobID.isEmpty ? nil : action.jobID,
                channel: channel?.isEmpty == false ? channel : nil,
                attachmentData: attachmentData,
                attachmentName: raw["attachmentName"] as? String,
                attachmentContentType: raw["attachmentContentType"] as? String,
                attachmentCaption: raw["attachmentCaption"] as? String,
                clientID: action.id,
                activationToken: activationToken
            )
            await OfflineMediaStore.shared.remove(path: attachmentPath)

        case .clockPunch:
            guard
                let imagePath = raw["imagePath"] as? String,
                let kind = raw["kind"] as? String,
                let latText = raw["lat"] as? String, let latitude = Double(latText),
                let lngText = raw["lng"] as? String, let longitude = Double(lngText),
                let accuracyText = raw["accuracy"] as? String, let accuracy = Double(accuracyText),
                let capturedText = raw["capturedAt"] as? String,
                let capturedAt = ISO8601DateFormatter().date(from: capturedText)
            else { throw HaloAPIError.malformedPayload }
            let bytes = try await Self.readFileData(URL(fileURLWithPath: imagePath))
            let attendanceOnly = (raw["attendanceOnly"] as? String) == "true" || (raw["attendanceOnly"] as? Bool) == true
            try await api.replayClockPunch(
                kind: kind,
                jobID: action.jobID,
                attendanceOnly: attendanceOnly,
                imageData: bytes,
                latitude: latitude,
                longitude: longitude,
                accuracy: accuracy,
                capturedAt: capturedAt,
                requestID: action.id,
                activationToken: activationToken
            )
            await OfflineMediaStore.shared.remove(path: imagePath)
            NotificationCenter.default.post(name: .haloClockStateChanged, object: nil)

        case .arrivalCheckIn:
            guard
                let imagePath = raw["imagePath"] as? String,
                let latText = raw["lat"] as? String, let latitude = Double(latText),
                let lngText = raw["lng"] as? String, let longitude = Double(lngText),
                let accuracyText = raw["accuracy"] as? String, let accuracy = Double(accuracyText),
                let capturedText = raw["capturedAt"] as? String,
                let capturedAt = ISO8601DateFormatter().date(from: capturedText)
            else { throw HaloAPIError.malformedPayload }

            let bytes = try await Self.readFileData(URL(fileURLWithPath: imagePath))
            _ = try await api.verifyCheckIn(
                jobID: action.jobID,
                latitude: latitude,
                longitude: longitude,
                accuracy: accuracy,
                capturedAt: capturedAt,
                imageData: bytes,
                requestID: action.id,
                activationToken: activationToken
            )
            await OfflineMediaStore.shared.remove(path: imagePath)
        }
    }
    private func shouldDiscardSuperseded(action: PendingFieldAction, error: Error, message: String) -> Bool {
        guard let apiError = error as? HaloAPIError,
              case let .http(status, _) = apiError else { return false }

        let lower = message.lowercased()
        if action.kind == PendingActionKind.taskToggle.rawValue {
            return (status == 400 || status == 409) && (
                lower.contains("unknown task")
                || lower.contains("task no longer exists")
                || lower.contains("checklist item no longer exists")
            )
        }

        if action.kind == PendingActionKind.workflowState.rawValue, status == 409 {
            return lower.contains("finish every required")
                || lower.contains("finish every checklist")
                || lower.contains("before review")
                || lower.contains("unsupported workflow")
        }

        return false
    }

    nonisolated private static func readFileData(_ url: URL) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try Data(contentsOf: url, options: [.mappedIfSafe])
        }.value
    }

}
