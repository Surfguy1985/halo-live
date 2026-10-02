import Foundation

enum JobBrowserScope: String, CaseIterable, Identifiable {
    case assigned = "My jobs", board = "Property board", history = "History"
    static func available(officeAccess: Bool) -> [Self] {
        officeAccess ? [.assigned, .board, .history] : [.assigned]
    }
    var id: String { rawValue }
    var apiValue: String {
        switch self { case .assigned: "assigned"; case .board: "board"; case .history: "history" }
    }
}

enum JobBrowserSort: String, CaseIterable, Identifiable {
    case priority = "Priority", scheduled = "Scheduled", property = "Property", recent = "Recently updated"
    var id: String { rawValue }
}

struct JobBrowserQuery {
    var text = ""
    var property = ""
    var kind: JobKind?
    var attentionOnly = false
    var sort: JobBrowserSort = .priority

    static func needsAttention(_ job: FieldJob) -> Bool {
        !job.isClosed && (job.state == .hold || job.flaggedCount > 0 || job.needsRework == true
            || job.unresolvedReworkCount > 0 || !(job.closeoutBlockers ?? []).isEmpty)
    }

    func apply(to jobs: [FieldJob]) -> [FieldJob] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return jobs.filter { job in
            let searchable = ([job.propertyName, job.unit, job.title, job.jobNo ?? "", job.scopeNotes ?? ""] + job.services).joined(separator: " ")
            return (property.isEmpty || property == job.propertyName)
                && (kind == nil || kind == job.kind)
                && (!attentionOnly || Self.needsAttention(job))
                && words.allSatisfy { searchable.localizedCaseInsensitiveContains($0) }
        }.sorted { lhs, rhs in
            switch sort {
            case .priority:
                let rank: (FieldJob) -> Int = { job in
                    if Self.needsAttention(job) { return 0 }
                    if job.priority == "red" { return 1 }
                    if job.priority == "yellow" { return 2 }
                    return 3
                }
                if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
            case .scheduled:
                let l = lhs.scheduledDate ?? "9999", r = rhs.scheduledDate ?? "9999"
                if l != r { return l < r }
            case .recent:
                let l = lhs.updatedAt ?? "", r = rhs.updatedAt ?? ""
                if l != r { return l > r }
            case .property: break
            }
            let p = lhs.propertyName.localizedStandardCompare(rhs.propertyName)
            if p != .orderedSame { return p == .orderedAscending }
            let u = lhs.unit.localizedStandardCompare(rhs.unit)
            if u != .orderedSame { return u == .orderedAscending }
            return lhs.id < rhs.id
        }
    }
}
