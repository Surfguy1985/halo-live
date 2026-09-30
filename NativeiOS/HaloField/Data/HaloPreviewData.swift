import Foundation

#if DEBUG
enum HaloPreviewData {
    static let jobs: [FieldJob] = [
        FieldJob(
            id: "preview-thornbury-2418",
            jobNo: "B44-2418",
            propertyID: "preview-thornbury",
            propertyName: "Thornbury at Chase Oaks",
            unit: "2418",
            kind: .turn,
            title: "Make Ready Package",
            services: ["Make Ready Package", "Wall Prep & Paint", "Vacant Unit Clean"],
            state: .active,
            rawStatus: "active",
            scheduledDate: Self.today,
            scheduledWindow: "8:00 AM",
            travelMinutes: 8,
            address: "Thornbury at Chase Oaks, Plano, TX",
            crewLeaderID: "preview-crew",
            crewLeaderName: "Archangel Crew 01",
            tasks: [
                JobTask(id: "t1", title: "Wall prep & paint", detail: "Living, bedrooms and trim", isComplete: true, requiresPhoto: true),
                JobTask(id: "t2", title: "Make ready", detail: "Punch list and fixture check", isComplete: false, requiresPhoto: true),
                JobTask(id: "t3", title: "Final clean", detail: "Turn-ready finish", isComplete: false, requiresPhoto: true)
            ],
            photoCount: 7,
            flaggedCount: 0,
            updatedAt: ISO8601DateFormatter().string(from: .now)
        ),
        FieldJob(
            id: "preview-avalon-1104",
            jobNo: "B44-1104",
            propertyID: "preview-avalon",
            propertyName: "Avalon",
            unit: "1104",
            kind: .maintenance,
            title: "Maintenance Repair",
            services: ["HVAC diagnostic", "Drywall patch"],
            state: .scheduled,
            rawStatus: "scheduled",
            scheduledDate: Self.today,
            scheduledWindow: "10:30 AM",
            travelMinutes: 14,
            address: "Avalon, Plano, TX",
            crewLeaderID: "preview-crew",
            crewLeaderName: "Archangel Crew 01",
            tasks: [
                JobTask(id: "a1", title: "Diagnose HVAC", detail: "Document issue before repair", isComplete: false, requiresPhoto: true),
                JobTask(id: "a2", title: "Repair drywall", detail: "Patch, texture and finish", isComplete: false, requiresPhoto: true)
            ],
            photoCount: 0,
            flaggedCount: 1,
            updatedAt: ISO8601DateFormatter().string(from: .now)
        ),
        FieldJob(
            id: "preview-emerson-803",
            jobNo: "B44-803",
            propertyID: "preview-emerson",
            propertyName: "The Emerson",
            unit: "803",
            kind: .turn,
            title: "Final Turn Clean",
            services: ["Vacant Unit Clean", "Final Walk"],
            state: .scheduled,
            rawStatus: "scheduled",
            scheduledDate: Self.today,
            scheduledWindow: "1:00 PM",
            travelMinutes: 11,
            address: "The Emerson, Frisco, TX",
            crewLeaderID: "preview-crew",
            crewLeaderName: "Archangel Crew 01",
            tasks: [
                JobTask(id: "e1", title: "Vacant unit clean", detail: nil, isComplete: false, requiresPhoto: true),
                JobTask(id: "e2", title: "Final walk", detail: nil, isComplete: false, requiresPhoto: true)
            ],
            photoCount: 2,
            flaggedCount: 0,
            updatedAt: ISO8601DateFormatter().string(from: .now)
        )
    ]

    private static var today: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }
}
#endif
