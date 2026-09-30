import Foundation
import SwiftUI

@MainActor
final class JobStore: ObservableObject {
    @Published var jobs: [FieldJob] = PreviewData.jobs
    @Published var selectedJobID: UUID?

    var nextJob: FieldJob? {
        jobs.first(where: { $0.state != .complete })
    }

    func advance(_ jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        let next: JobState = switch jobs[index].state {
        case .scheduled: .enRoute
        case .enRoute: .arrived
        case .arrived: .active
        case .active: .proof
        case .proof: .review
        case .review: .complete
        case .complete: .complete
        case .hold: .hold
        }
        withAnimation(.snappy(duration: 0.35)) {
            jobs[index].state = next
        }
    }

    func toggleTask(jobID: UUID, taskID: UUID) {
        guard let j = jobs.firstIndex(where: { $0.id == jobID }),
              let t = jobs[j].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        withAnimation(.snappy) {
            jobs[j].tasks[t].isComplete.toggle()
        }
    }
}

enum PreviewData {
    static let jobs: [FieldJob] = [
        FieldJob(
            id: UUID(),
            propertyName: "Thornbury at Chase Oaks",
            unit: "2418",
            kind: .turn,
            title: "Make Ready",
            state: .scheduled,
            scheduledWindow: "8:00–11:00 AM",
            travelMinutes: 12,
            address: "Plano, TX",
            tasks: [
                .init(id: UUID(), title: "Patch drywall", detail: "Bedroom wall · 2 areas", isComplete: true, requiresPhoto: true),
                .init(id: UUID(), title: "Paint walls", detail: "Eggshell white", isComplete: true, requiresPhoto: true),
                .init(id: UUID(), title: "Replace bedroom blind", detail: "34-inch white cordless blind", isComplete: false, requiresPhoto: true),
                .init(id: UUID(), title: "Final clean", detail: "Kitchen, bath, floors", isComplete: false, requiresPhoto: true)
            ],
            photoCount: 8,
            flaggedCount: 1
        ),
        FieldJob(
            id: UUID(),
            propertyName: "Thornbury at Chase Oaks",
            unit: "1104",
            kind: .maintenance,
            title: "Garbage Disposal",
            state: .scheduled,
            scheduledWindow: "11:30 AM–1:00 PM",
            travelMinutes: nil,
            address: "Plano, TX",
            tasks: [
                .init(id: UUID(), title: "Diagnose disposal", detail: nil, isComplete: false, requiresPhoto: true),
                .init(id: UUID(), title: "Repair or replace", detail: nil, isComplete: false, requiresPhoto: true)
            ],
            photoCount: 0,
            flaggedCount: 0
        ),
        FieldJob(
            id: UUID(),
            propertyName: "The Emerson",
            unit: "803",
            kind: .turn,
            title: "Paint + Punch",
            state: .scheduled,
            scheduledWindow: "2:00–4:30 PM",
            travelMinutes: 18,
            address: "Frisco, TX",
            tasks: [
                .init(id: UUID(), title: "Paint touchups", detail: nil, isComplete: false, requiresPhoto: true),
                .init(id: UUID(), title: "Final punch", detail: nil, isComplete: false, requiresPhoto: true)
            ],
            photoCount: 0,
            flaggedCount: 0
        )
    ]
}
