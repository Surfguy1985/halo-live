import Foundation

struct HaloIntentJobSnapshot: Codable, Sendable {
    let id: String
    let unit: String
    let propertyName: String
    let title: String
    let state: String
    let scheduledWindow: String
    let address: String
}

enum HaloIntentStore {
    private static let key = "halo.intent.next-job"

    static func save(_ job: FieldJob?) {
        guard let job else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }

        let snapshot = HaloIntentJobSnapshot(
            id: job.id,
            unit: job.unit,
            propertyName: job.propertyName,
            title: job.title,
            state: job.state.rawValue,
            scheduledWindow: job.scheduledWindow,
            address: job.address
        )

        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> HaloIntentJobSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HaloIntentJobSnapshot.self, from: data)
    }
}
