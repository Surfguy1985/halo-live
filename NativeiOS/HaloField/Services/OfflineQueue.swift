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

    init(jobID: String, kind: String, payload: Data) {
        self.id = UUID()
        self.createdAt = .now
        self.jobID = jobID
        self.kind = kind
        self.payload = payload
        self.retryCount = 0
        self.lastError = nil
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
        try? context.save()
    }

    func remove(_ action: PendingFieldAction, context: ModelContext) {
        context.delete(action)
        try? context.save()
    }
}
