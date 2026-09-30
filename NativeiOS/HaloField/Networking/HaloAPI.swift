import Foundation

enum HaloAPIError: LocalizedError {
    case invalidResponse
    case http(Int, String)
    case malformedPayload
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "HALO returned an invalid response."
        case .http(let status, let message): "HALO sync failed (\(status)): \(message)"
        case .malformedPayload: "HALO returned job data the app could not read."
        case .transport(let error): error.localizedDescription
        }
    }
}

actor HaloAPI {
    static let shared = HaloAPI()

    let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = URL(string: "https://archangel-halo.replit.app")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchJobs(activationToken: String) async throws -> [FieldJob] {
        let data = try await request(
            path: "/api/native/field-feed",
            bearerToken: activationToken
        )
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let raw = root["jobs"] as? [Any]
        else {
            throw HaloAPIError.malformedPayload
        }

        return raw.compactMap { item in
            guard let row = item as? [String: Any] else { return nil }
            return Self.mapJob(row)
        }
        .filter { !$0.id.isEmpty }
        .sorted(by: Self.sortJobs)
    }

    func updateJobStatus(id: String, status: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["status": status])
        _ = try await request(path: "/api/jobs/\(id)", method: "PATCH", body: body)
    }

    private func request(path: String, method: String = "GET", body: Data? = nil, bearerToken: String? = nil) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw HaloAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearerToken, !bearerToken.isEmpty {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw HaloAPIError.invalidResponse
            }
            guard 200..<300 ~= http.statusCode else {
                let message = Self.serverMessage(data) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                throw HaloAPIError.http(http.statusCode, message)
            }
            return data
        } catch let error as HaloAPIError {
            throw error
        } catch {
            throw HaloAPIError.transport(error)
        }
    }

    nonisolated private static func mapJob(_ row: [String: Any]) -> FieldJob? {
        guard let id = string(row["id"]), !id.isEmpty else { return nil }

        let propertyName = string(row["propertyName"]) ?? "Property"
        let unit = string(row["unitNo"]) ?? string(row["unit"]) ?? "—"
        let category = string(row["category"])
        let description = string(row["description"]) ?? category ?? "Job"
        let services = stringArray(row["services"])
        let serviceNames = services.isEmpty ? splitServices(description) : services
        let title = category ?? serviceNames.first ?? description
        let rawStatus = (string(row["status"]) ?? "open").lowercased()
        let boardStatus = (string(row["boardStatus"]) ?? "").lowercased()

        let kind: JobKind = {
            let haystack = ([category, description] + serviceNames).compactMap { $0 }.joined(separator: " ").lowercased()
            return haystack.contains("maintenance") || haystack.contains("repair") ? .maintenance : .turn
        }()

        let tasks = serviceNames.prefix(12).enumerated().map { index, service in
            JobTask(
                id: "\(id)-task-\(index)",
                title: service,
                detail: nil,
                isComplete: rawStatus == "complete" || rawStatus == "paid" || rawStatus == "cleared",
                requiresPhoto: true
            )
        }

        let state = mapState(status: rawStatus, boardStatus: boardStatus)
        let scheduledOn = string(row["scheduledOn"])
        let scheduledTime = string(row["scheduledTime"])
        let window = displayWindow(date: scheduledOn, time: scheduledTime)

        return FieldJob(
            id: id,
            jobNo: string(row["jobNo"]),
            propertyID: string(row["propertyId"]),
            propertyName: propertyName,
            unit: unit,
            kind: kind,
            title: title,
            services: serviceNames,
            state: state,
            rawStatus: rawStatus,
            scheduledDate: scheduledOn,
            scheduledWindow: window,
            travelMinutes: nil,
            address: propertyName,
            crewLeaderID: string(row["crewLeaderId"]),
            crewLeaderName: string(row["crewLeaderName"]),
            tasks: tasks.isEmpty ? [
                JobTask(id: "\(id)-task-0", title: description, detail: nil, isComplete: state == .complete, requiresPhoto: true)
            ] : tasks,
            photoCount: int(row["photoCount"]) ?? 0,
            flaggedCount: rawStatus == "hold" || rawStatus == "flagged" ? 1 : 0,
            updatedAt: string(row["updatedAt"]) ?? string(row["createdAt"])
        )
    }

    nonisolated private static func mapState(status: String, boardStatus: String) -> JobState {
        switch status {
        case "complete", "completed", "paid", "cleared": return .complete
        case "hold", "flagged", "cancelled", "canceled": return .hold
        case "active", "in_progress", "on_site", "dispatched": return .active
        case "review", "billing": return .review
        default:
            if boardStatus == "completed" || boardStatus == "billing" { return .review }
            if boardStatus == "filled" && status == "active" { return .active }
            return .scheduled
        }
    }

    nonisolated private static func splitServices(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    nonisolated private static func displayWindow(date: String?, time: String?) -> String {
        if let time, !time.isEmpty { return time }
        guard let date, !date.isEmpty else { return "Unscheduled" }

        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd"
        guard let parsed = input.date(from: date) else { return date }

        let output = DateFormatter()
        output.dateFormat = Calendar.current.isDateInToday(parsed) ? "'Today'" : "EEE · MMM d"
        return output.string(from: parsed)
    }

    nonisolated private static func sortJobs(_ lhs: FieldJob, _ rhs: FieldJob) -> Bool {
        let rank: (FieldJob) -> Int = { job in
            switch job.state {
            case .active, .arrived, .enRoute: 0
            case .scheduled: 1
            case .proof, .review: 2
            case .hold: 3
            case .complete: 4
            }
        }

        let lRank = rank(lhs), rRank = rank(rhs)
        if lRank != rRank { return lRank < rRank }

        switch (lhs.scheduledDate, rhs.scheduledDate) {
        case let (l?, r?) where l != r: return l < r
        default: return lhs.propertyName.localizedCaseInsensitiveCompare(rhs.propertyName) == .orderedAscending
        }
    }

    nonisolated private static func string(_ value: Any?) -> String? {
        switch value {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }

    nonisolated private static func stringArray(_ value: Any?) -> [String] {
        guard let items = value as? [Any] else { return [] }
        return items.compactMap(string).filter { !$0.isEmpty }
    }

    nonisolated private static func int(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }

    nonisolated private static func serverMessage(_ data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = json["error"] as? String
        else { return nil }
        return message
    }
}
