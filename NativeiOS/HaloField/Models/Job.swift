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
        case .enRoute: "Verify Arrival"
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
    let id: String
    var title: String
    var detail: String?
    var isComplete: Bool
    var requiresPhoto: Bool
}

struct ReworkItem: Identifiable, Codable, Hashable {
    let id: String
    let index: Int
    var text: String
    var isComplete: Bool
}

struct FieldJob: Identifiable, Codable, Hashable {
    let id: String
    var jobNo: String?
    var propertyID: String?
    var propertyName: String
    var unit: String
    var kind: JobKind
    var title: String
    var services: [String]
    var state: JobState
    var rawStatus: String
    var scheduledDate: String?
    var scheduledWindow: String
    var travelMinutes: Int?
    var address: String
    var propertyLatitude: Double?
    var propertyLongitude: Double?
    var crewLeaderID: String?
    var crewLeaderName: String?
    var tasks: [JobTask]
    var photoCount: Int
    var beforePhotoCount: Int = 0
    var afterPhotoCount: Int = 0
    var flaggedCount: Int
    var updatedAt: String?
    var needsRework: Bool?
    var reworkNotes: String?
    var reworkItems: [ReworkItem]?
    var closeoutStage: String?
    var closeoutBlockers: [String]?
    var finalWalkAt: String?
    var readyForWalk: Bool?
    var walkVerified: Bool?
    var scopeNotes: String? = nil
    var bedrooms: Int? = nil
    var priority: String? = nil

    var completedTasks: Int { tasks.filter(\.isComplete).count }
    var scopeItemCount: Int { max(tasks.count, services.count) }
    var progress: Double {
        guard !tasks.isEmpty else { return 0 }
        return Double(completedTasks) / Double(tasks.count)
    }

    var isClosed: Bool { state == .complete }
    var unresolvedReworkCount: Int { (reworkItems ?? []).filter { !$0.isComplete }.count }
}
