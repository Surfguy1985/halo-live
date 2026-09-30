import Foundation

enum JobKind: String, Codable, CaseIterable {
    case turn = "TURN"
    case maintenance = "MAINTENANCE"
}

enum JobState: String, Codable, CaseIterable {
    case scheduled, enRoute, arrived, active, proof, review, complete, hold

    var actionTitle: String {
        switch self {
        case .scheduled: "Start Route"
        case .enRoute: "I’ve Arrived"
        case .arrived: "Check In"
        case .active: "Continue Job"
        case .proof: "Finish Proof"
        case .review: "Submit for Review"
        case .complete: "Completed"
        case .hold: "View Hold"
        }
    }
}

struct JobTask: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var detail: String?
    var isComplete: Bool
    var requiresPhoto: Bool
}

struct FieldJob: Identifiable, Codable, Hashable {
    let id: UUID
    var propertyName: String
    var unit: String
    var kind: JobKind
    var title: String
    var state: JobState
    var scheduledWindow: String
    var travelMinutes: Int?
    var address: String
    var tasks: [JobTask]
    var photoCount: Int
    var flaggedCount: Int

    var completedTasks: Int { tasks.filter(\.isComplete).count }
    var progress: Double {
        guard !tasks.isEmpty else { return 0 }
        return Double(completedTasks) / Double(tasks.count)
    }
}
