import CryptoKit
import Foundation

actor OfflineJobCache {
    static let shared = OfflineJobCache()

    private struct Snapshot: Codable {
        let savedAt: Date
        let jobs: [FieldJob]
    }

    func load(token: String) throws -> (jobs: [FieldJob], savedAt: Date)? {
        let url = try snapshotURL(token: token)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        return (snapshot.jobs, snapshot.savedAt)
    }

    func save(jobs: [FieldJob], token: String) throws {
        let snapshot = Snapshot(savedAt: .now, jobs: jobs)
        let data = try JSONEncoder().encode(snapshot)
        let url = try snapshotURL(token: token)
        try data.write(to: url, options: .atomic)
    }

    func remove(token: String) throws {
        let url = try snapshotURL(token: token)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func snapshotURL(token: String) throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("HaloFieldCache", isDirectory: true)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let digest = SHA256.hash(data: Data(token.utf8))
        let key = digest.map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent("\(key).json")
    }
}
