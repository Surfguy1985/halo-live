import Foundation
import SwiftData

@Model
final class PendingFieldAction {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var jobID: String
    var kind: String
    var payload: Data
    var retryCount: Int

    init(jobID: String, kind: String, payload: Data) {
        self.id = UUID()
        self.createdAt = .now
        self.jobID = jobID
        self.kind = kind
        self.payload = payload
        self.retryCount = 0
    }
}

@MainActor
final class OfflineQueue {
    static let shared = OfflineQueue()

    func enqueue(jobID: String, kind: String, payload: Data, context: ModelContext) {
        context.insert(PendingFieldAction(jobID: jobID, kind: kind, payload: payload))
        try? context.save()
    }

    func pending(in context: ModelContext) throws -> [PendingFieldAction] {
        try context.fetch(FetchDescriptor<PendingFieldAction>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    func remove(_ action: PendingFieldAction, context: ModelContext) {
        context.delete(action)
        try? context.save()
    }
}