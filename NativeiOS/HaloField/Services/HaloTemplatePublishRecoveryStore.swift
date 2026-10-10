import Foundation

/// Durable, token-free storage for publishes whose commit result is unknown.
/// The original proposal is the recovery identity and cannot be replaced by a
/// different proposal that reuses its request ID.
actor HaloTemplatePublishRecoveryStore {
    enum Failure: Error, Equatable {
        case corruptStore
        case unsupportedVersion
        case requestIdentityConflict
    }

    private struct Payload: Codable {
        let version: Int
        var records: [HaloTemplatePublishing.UncertainPublish]
    }

    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static func live() throws -> HaloTemplatePublishRecoveryStore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return HaloTemplatePublishRecoveryStore(
            fileURL: support
                .appendingPathComponent("HALO", isDirectory: true)
                .appendingPathComponent("uncertain-template-publishes.json")
        )
    }

    func records() throws -> [HaloTemplatePublishing.UncertainPublish] {
        try readPayload().records.sorted { $0.detectedAt < $1.detectedAt }
    }

    /// Returns false when this exact request is already pending. A caller must
    /// reconcile that record instead of sending the publish again.
    @discardableResult
    func save(_ record: HaloTemplatePublishing.UncertainPublish) throws -> Bool {
        var payload = try readPayload()
        if let existing = payload.records.first(where: { $0.id == record.id }) {
            guard existing.originalProposal == record.originalProposal else {
                throw Failure.requestIdentityConflict
            }
            return false
        }
        payload.records.append(record)
        try write(payload)
        return true
    }

    func remove(requestID: UUID) throws {
        var payload = try readPayload()
        let originalCount = payload.records.count
        payload.records.removeAll { $0.id == requestID }
        guard payload.records.count != originalCount else { return }
        try write(payload)
    }

    private func readPayload() throws -> Payload {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Payload(version: 1, records: [])
        }
        do {
            let payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: fileURL))
            guard payload.version == 1 else { throw Failure.unsupportedVersion }
            guard Set(payload.records.map(\.id)).count == payload.records.count else {
                throw Failure.corruptStore
            }
            return payload
        } catch let failure as Failure {
            throw failure
        } catch is DecodingError {
            throw Failure.corruptStore
        }
    }

    private func write(_ payload: Payload) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableDirectory = directory
        try mutableDirectory.setResourceValues(resourceValues)

        let data = try JSONEncoder().encode(payload)
        try data.write(to: fileURL, options: [.atomic])

#if os(iOS) && !targetEnvironment(simulator)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
#endif
    }
}
