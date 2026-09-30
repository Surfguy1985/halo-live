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

    init(jobID: String, kind: String, payload: Data) {
        self.id = UUID()
        self.createdAt = .now
        self.jobID = jobID
        self.kind = kind
        self.payload = payload
        self.retryCount = 0
        self.lastError = nil
        self.nextAttemptAt = nil
    }
}

@MainActor
final class OfflineQueue {
    static let shared = OfflineQueue()

    func enqueue(
        jobID: String,
        kind: PendingActionKind,
        payload: [String: String],
        context: ModelContext
    ) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        context.insert(PendingFieldAction(jobID: jobID, kind: kind.rawValue, payload: data))
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

    func count(in context: ModelContext) -> Int {
        (try? pending(in: context).count) ?? 0
    }

    func markRetry(_ action: PendingFieldAction, error: String, context: ModelContext) {
        action.retryCount += 1
        action.lastError = error
        let exponent = min(action.retryCount, 6)
        let delay = min(pow(2.0, Double(exponent)) * 5.0, 300.0)
        action.nextAttemptAt = Date().addingTimeInterval(delay)
        try? context.save()
    }

    func ready(in context: ModelContext, now: Date = .now) throws -> [PendingFieldAction] {
        try pending(in: context).filter { action in
            guard let retryAt = action.nextAttemptAt else { return true }
            return retryAt <= now
        }
    }

    func remove(_ action: PendingFieldAction, context: ModelContext) {
        context.delete(action)
        try? context.save()
    }
}


extension Notification.Name {
    static let haloPendingActionCreated = Notification.Name("halo.pendingActionCreated")
}
