import CryptoKit
import Foundation
import SwiftData

enum PendingActionKind: String, Codable {
    case workflowState
    case taskToggle
    case proofCaptured
    case turnHandoff
    case reworkToggle
    case messageSend
    case clockPunch
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
    var requiresAttention: Bool?

    init(id: UUID = UUID(), jobID: String, kind: String, payload: Data, ownerKey: String?) {
        self.id = id
        self.createdAt = .now
        self.jobID = jobID
        self.kind = kind
        self.payload = payload
        self.retryCount = 0
        self.lastError = nil
        self.nextAttemptAt = nil
        self.ownerKey = ownerKey
        self.requiresAttention = false
    }
}

@MainActor
final class OfflineQueue {
    static let shared = OfflineQueue()

    @discardableResult
    func enqueue(
        id: UUID = UUID(),
        jobID: String,
        kind: PendingActionKind,
        payload: [String: String],
        activationToken: String?,
        context: ModelContext
    ) -> UUID? {
        guard
            let activationToken,
            !activationToken.isEmpty,
            let data = try? JSONSerialization.data(withJSONObject: payload)
        else { return nil }

        context.insert(
            PendingFieldAction(
                id: id,
                jobID: jobID,
                kind: kind.rawValue,
                payload: data,
                ownerKey: Self.ownerKey(for: activationToken)
            )
        )
        try? context.save()
        NotificationCenter.default.post(name: .haloPendingActionCreated, object: nil)
        return id
    }

    func pending(in context: ModelContext) throws -> [PendingFieldAction] {
        try context.fetch(
            FetchDescriptor<PendingFieldAction>(
                sortBy: [SortDescriptor(\.createdAt)]
            )
        )
    }

    func counts(in context: ModelContext, activationToken: String?) -> (pending: Int, attention: Int) {
        guard let activationToken, !activationToken.isEmpty else { return (0, 0) }
        let key = Self.ownerKey(for: activationToken)
        let scoped = (try? pending(in: context).filter { $0.ownerKey == key }) ?? []
        return (
            scoped.filter { $0.requiresAttention != true }.count,
            scoped.filter { $0.requiresAttention == true }.count
        )
    }

    func markPermanentFailure(_ action: PendingFieldAction, error: String, context: ModelContext) {
        action.lastError = error
        action.requiresAttention = true
        action.nextAttemptAt = nil
        try? context.save()
    }

    func scopedActions(in context: ModelContext, activationToken: String?) -> [PendingFieldAction] {
        guard let activationToken, !activationToken.isEmpty else { return [] }
        let key = Self.ownerKey(for: activationToken)
        return ((try? pending(in: context)) ?? []).filter { $0.ownerKey == key }
    }

    func retryAttention(_ action: PendingFieldAction, context: ModelContext) {
        action.requiresAttention = false
        action.lastError = nil
        action.nextAttemptAt = nil
        try? context.save()
        NotificationCenter.default.post(name: .haloPendingActionCreated, object: nil)
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
            guard action.ownerKey == key, action.requiresAttention != true else { return false }
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


actor OfflineMediaStore {
    static let shared = OfflineMediaStore()

    func save(_ data: Data, preferredExtension: String = "bin") throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("HaloOutbox", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let ext = preferredExtension
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .lowercased()
        let url = base.appendingPathComponent("\(UUID().uuidString).\(ext.isEmpty ? "bin" : ext)")
        try data.write(to: url, options: [.atomic])
        return url
    }

    func remove(path: String?) {
        guard let path, !path.isEmpty else { return }
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
    }
}
