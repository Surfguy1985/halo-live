import CryptoKit
import Foundation
import SwiftData

enum PendingActionKind: String, Codable {
    case workflowState
    case taskToggle
    case proofCaptured
}

@Model
final class PendingFieldAction {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var jobID: String
    var kind: String
    var payload: Data
    var retryCount: Int
    var lastError: String?
    var nextAttemptAt: Date?
    var ownerKey: String?

    init(jobID: String, kind: String, payload: Data, ownerKey: String?) {
        self.id = UUID()
        self.createdAt = .now
        self.jobID = jobID
        self.kind = kind
        self.payload = payload
        self.retryCount = 0
        self.lastError = nil
        self.nextAttemptAt = nil
        self.ownerKey = ownerKey
    }
}

@MainActor
final class OfflineQueue {
    static let shared = OfflineQueue()

    func enqueue(
        jobID: String,
        kind: PendingActionKind,
        payload: [String: String],
        activationToken: String?,
        context: ModelContext
    ) {
        guard
            let activationToken,
            !activationToken.isEmpty,
            let data = try? JSONSerialization.data(withJSONObject: payload)
        else { return }

        context.insert(
            PendingFieldAction(
                jobID: jobID,
                kind: kind.rawValue,
                payload: data,
                ownerKey: Self.ownerKey(for: activationToken)
            )
        )
        try? context.save()
        NotificationCenter.default.post(name: .haloPendingActionCreated, object: nil)
    }

    func pending(in context: ModelContext) throws -> [PendingFieldAction] {
        try context.fetch(
            FetchDescriptor<PendingFieldAction>(
                sortBy: [SortDescriptor(\.createdAt)]
            )
        )
    }

    func count(in context: ModelContext, activationToken: String?) -> Int {
        guard let activationToken, !activationToken.isEmpty else { return 0 }
        let key = Self.ownerKey(for: activationToken)
        return (try? pending(in: context).filter { $0.ownerKey == key }.count) ?? 0
    }

    func markRetry(_ action: PendingFieldAction, error: String, context: ModelContext) {
        action.retryCount += 1
        action.lastError = error
        let exponent = min(action.retryCount, 6)
        let delay = min(pow(2.0, Double(exponent)) * 5.0, 300.0)
        action.nextAttemptAt = Date().addingTimeInterval(delay)
        try? context.save()
    }

    func ready(
        in context: ModelContext,
        activationToken: String,
        now: Date = .now
    ) throws -> [PendingFieldAction] {
        let key = Self.ownerKey(for: activationToken)
        return try pending(in: context).filter { action in
            guard action.ownerKey == key else { return false }
            guard let retryAt = action.nextAttemptAt else { return true }
            return retryAt <= now
        }
    }

    private static func ownerKey(for activationToken: String) -> String {
        SHA256.hash(data: Data(activationToken.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func remove(_ action: PendingFieldAction, context: ModelContext) {
        context.delete(action)
        try? context.save()
    }
}


extension Notification.Name {
    static let haloPendingActionCreated = Notification.Name("halo.pendingActionCreated")
}
