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
            path: "/api/native/v1/field-feed",
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

    struct CheckInResult: Sendable {
        let distanceMeters: Int
        let allowedRadiusMeters: Int
        let accuracyMeters: Double
        let verifiedAt: String
    }

    func verifyCheckIn(
        jobID: String,
        latitude: Double,
        longitude: Double,
        accuracy: Double,
        capturedAt: Date,
        activationToken: String
    ) async throws -> CheckInResult {
        let formatter = ISO8601DateFormatter()
        let body = try JSONSerialization.data(withJSONObject: [
            "jobId": jobID,
            "lat": latitude,
            "lng": longitude,
            "accuracy": accuracy,
            "capturedAt": formatter.string(from: capturedAt)
        ])
        let data = try await request(
            path: "/api/native/v1/check-in",
            method: "POST",
            body: body,
            bearerToken: activationToken
        )
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            (root["verified"] as? Bool) == true
        else { throw HaloAPIError.malformedPayload }

        return CheckInResult(
            distanceMeters: (root["distanceMeters"] as? NSNumber)?.intValue ?? 0,
            allowedRadiusMeters: (root["allowedRadiusMeters"] as? NSNumber)?.intValue ?? 300,
            accuracyMeters: (root["accuracyMeters"] as? NSNumber)?.doubleValue ?? accuracy,
            verifiedAt: root["verifiedAt"] as? String ?? formatter.string(from: .now)
        )
    }

    func createTurnHandoff(
        handoffID: UUID,
        sourceJobID: String,
        summary: String,
        detail: String,
        urgency: String,
        materialEstimate: String,
        activationToken: String
    ) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "handoffId": handoffID.uuidString,
            "jobId": sourceJobID,
            "summary": summary,
            "detail": detail,
            "urgency": urgency,
            "materialEstimate": materialEstimate
        ])
        _ = try await request(
            path: "/api/native/v1/handoffs",
            method: "POST",
            body: body,
            bearerToken: activationToken
        )
    }

    func sendFieldAction(
        id: UUID,
        jobID: String,
        kind: String,
        payload: [String: Any],
        activationToken: String
    ) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "id": id.uuidString,
            "jobId": jobID,
            "kind": kind,
            "payload": payload
        ])
        _ = try await request(
            path: "/api/native/v1/actions",
            method: "POST",
            body: body,
            bearerToken: activationToken
        )
    }

    func requestProofUpload(
        jobID: String,
        size: Int,
        activationToken: String
    ) async throws -> (uploadURL: URL, objectPath: String) {
        let body = try JSONSerialization.data(withJSONObject: [
            "jobId": jobID,
            "size": size,
            "contentType": "image/jpeg"
        ])
        let data = try await request(
            path: "/api/native/v1/proofs/request-upload",
            method: "POST",
            body: body,
            bearerToken: activationToken
        )
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let upload = root["uploadURL"] as? String,
            let url = URL(string: upload),
            let objectPath = root["objectPath"] as? String
        else { throw HaloAPIError.malformedPayload }
        return (url, objectPath)
    }

    func uploadProofBytes(_ data: Data, to url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 60
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw HaloAPIError.invalidResponse
            }
            guard 200..<300 ~= http.statusCode else {
                throw HaloAPIError.http(http.statusCode, "Proof upload failed")
            }
        } catch let error as HaloAPIError {
            throw error
        } catch {
            throw HaloAPIError.transport(error)
        }
    }

    func registerProof(
        metadata: ProofMetadata,
        objectPath: String,
        activationToken: String
    ) async throws {
        var object: [String: Any] = [
            "proofId": metadata.proofID,
            "jobId": metadata.jobID,
            "storagePath": objectPath,
            "phase": metadata.phase.lowercased() == "after" ? "after" : "before"
        ]
        if let lat = metadata.latitude { object["lat"] = lat }
        if let lng = metadata.longitude { object["lng"] = lng }
        if let accuracy = metadata.horizontalAccuracy { object["accuracy"] = accuracy }
        if let task = metadata.taskTitle { object["note"] = task }

        let body = try JSONSerialization.data(withJSONObject: object)
        _ = try await request(
            path: "/api/native/v1/proofs/register",
            method: "POST",
            body: body,
            bearerToken: activationToken
        )
    }

    func updateJobStatus(id: String, status: String, activationToken: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["status": status])
        _ = try await request(
            path: "/api/jobs/\(id)",
            method: "PATCH",
            body: body,
            bearerToken: activationToken
        )
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
        let propertyAddress = string(row["propertyAddress"])
        let propertyCity = string(row["propertyCity"])
        let unit = string(row["unitNo"]) ?? string(row["unit"]) ?? "—"
        let category = string(row["category"])
        let description = string(row["description"]) ?? category ?? "Job"
        let services = stringArray(row["services"])
        let serviceNames = services.isEmpty ? splitServices(description) : services
        let serverTasks = taskArray(row["tasks"])
        let title = category ?? serviceNames.first ?? description
        let rawStatus = (string(row["status"]) ?? "open").lowercased()
        let boardStatus = (string(row["boardStatus"]) ?? "").lowercased()

        let kind: JobKind = {
            let haystack = ([category, description] + serviceNames).compactMap { $0 }.joined(separator: " ").lowercased()
            return haystack.contains("maintenance") || haystack.contains("repair") ? .maintenance : .turn
        }()

        let tasks: [JobTask] = serverTasks.isEmpty
            ? serviceNames.prefix(12).enumerated().map { index, service in
                JobTask(
                    id: "\(id)-task-\(index)",
                    title: service,
                    detail: nil,
                    isComplete: rawStatus == "complete" || rawStatus == "paid" || rawStatus == "cleared",
                    requiresPhoto: true
                )
            }
            : serverTasks

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
            address: [propertyAddress, propertyCity].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ").isEmpty
                ? propertyName
                : [propertyAddress, propertyCity].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "),
            propertyLatitude: double(row["propertyLatitude"]),
            propertyLongitude: double(row["propertyLongitude"]),
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

    nonisolated private static func taskArray(_ value: Any?) -> [JobTask] {
        guard let items = value as? [Any] else { return [] }
        return items.compactMap { item in
            guard
                let row = item as? [String: Any],
                let id = string(row["id"]),
                !id.isEmpty,
                let title = string(row["title"]),
                !title.isEmpty
            else { return nil }

            return JobTask(
                id: id,
                title: title,
                detail: string(row["detail"]),
                isComplete: (row["isComplete"] as? Bool) ?? false,
                requiresPhoto: (row["requiresPhoto"] as? Bool) ?? true
            )
        }
    }

    nonisolated private static func double(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
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
