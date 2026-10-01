import CoreLocation
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

struct TurnHandoff: Identifiable, Hashable, Sendable {
    let id: String
    let jobNo: String?
    let propertyName: String
    let address: String
    let unit: String
    let summary: String
    let dueBy: String?
    let createdAt: String?
}

struct HaloProofPair: Identifiable, Hashable, Sendable {
    let id: String
    let area: String?
    let beforeURL: String?
    let afterURL: String?
}

struct HaloMessageAttachment: Identifiable, Hashable, Sendable {
    let id: String
    let kind: String
    let url: String?
    let name: String?
    let caption: String?
    let title: String?
    let status: String?
    let actionTitle: String?
    let actionSummary: String?
    let beforeURL: String?
    let afterURL: String?
    let proofPairs: [HaloProofPair]
}

struct HaloMessage: Identifiable, Hashable, Sendable {
    let id: String
    let channel: String
    let threadName: String?
    let from: String
    let author: String
    let text: String
    let unitID: String?
    let unitLabel: String?
    let at: String?
    let read: Bool
    let attachments: [HaloMessageAttachment]
}

struct HaloGPSSession: Identifiable, Hashable, Sendable {
    let id: String
    let token: String
    let unitID: String?
    let property: String?
    let unitNumber: String?
    let active: Bool
    let latitude: Double?
    let longitude: Double?
    let accuracy: Double?
    let capturedAt: String?
    let consentedAt: String?
    let expiresAt: String?
}

struct HaloClockEntry: Hashable, Sendable {
    let id: String
    let jobID: String?
    let property: String?
    let unitNumber: String?
    let running: Bool
    let status: String
    let reviewStatus: String
    let startedAt: String?
    let workedMs: Int
    let pauseReason: String?
    let sessionType: String
}

struct HaloClockStatus: Hashable, Sendable {
    let configured: Bool
    let employeeID: String?
    let entry: HaloClockEntry?
}

struct HaloGrokTurn: Hashable, Sendable {
    let role: String
    let content: String
}

struct HaloGrokReply: Hashable, Sendable {
    let reply: String
    let model: String
    let groundedAt: String?
}

struct HaloActivationInfo: Hashable, Sendable {
    let crewID: String
    let crewName: String
    let expiresAt: String?
    let nativePushDeliveryConfigured: Bool
}

actor HaloAPI {
    static let shared = HaloAPI()
    static let connectionRevision = "HALO-CONNECT-2"

    let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = URL(string: "https://halo-back-office-copy-1d779ace.base44.app")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func validateActivation(token: String) async throws -> HaloActivationInfo {
        let body = try JSONSerialization.data(withJSONObject: ["action": "validate"])
        let data = try await request(
            path: "/functions/nativeFieldMobile",
            method: "POST",
            body: body,
            bearerToken: token
        )

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            (root["ok"] as? Bool) == true,
            let crew = root["crew"] as? [String: Any],
            let crewID = Self.string(crew["id"]),
            let crewName = Self.string(crew["name"])
        else {
            throw HaloAPIError.malformedPayload
        }

        let capabilities = root["capabilities"] as? [String: Any]
        return HaloActivationInfo(
            crewID: crewID,
            crewName: crewName,
            expiresAt: Self.string(root["expiresAt"]),
            nativePushDeliveryConfigured: (capabilities?["nativePushDeliveryConfigured"] as? Bool) ?? false
        )
    }

    func fetchJobs(activationToken: String) async throws -> [FieldJob] {
        let body = try JSONSerialization.data(withJSONObject: ["action": "feed"])
        let data = try await request(
            path: "/functions/nativeFieldMobile",
            method: "POST",
            body: body,
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
        requestID: UUID,
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
        var object = try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
        object["action"] = "checkIn"
        object["idempotencyKey"] = requestID.uuidString
        let payload = try JSONSerialization.data(withJSONObject: object)
        let data = try await request(
            path: "/functions/nativeFieldMobile",
            method: "POST",
            body: payload,
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

    func fetchOpenTurnHandoffs(activationToken: String) async throws -> [TurnHandoff] {
        let body = try JSONSerialization.data(withJSONObject: ["action": "handoffsOpen"])
        let data = try await request(
            path: "/functions/nativeFieldMobile",
            method: "POST",
            body: body,
            bearerToken: activationToken
        )
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = root["handoffs"] as? [[String: Any]]
        else { throw HaloAPIError.malformedPayload }

        return rows.compactMap { row in
            guard
                let id = Self.string(row["id"]),
                !id.isEmpty
            else { return nil }

            let propertyName = Self.string(row["propertyName"]) ?? "Property"
            let addressParts = [
                Self.string(row["propertyAddress"]),
                Self.string(row["propertyCity"])
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

            return TurnHandoff(
                id: id,
                jobNo: Self.string(row["jobNo"]),
                propertyName: propertyName,
                address: addressParts.isEmpty ? propertyName : addressParts.joined(separator: ", "),
                unit: Self.string(row["unitNo"]) ?? "—",
                summary: Self.string(row["description"]) ?? "Turn handoff",
                dueBy: Self.string(row["flexDueBy"]),
                createdAt: Self.string(row["createdAt"])
            )
        }
    }

    func claimTurnHandoff(id: String, activationToken: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "action": "handoffClaim",
            "handoffId": id
        ])
        _ = try await request(
            path: "/functions/nativeFieldMobile",
            method: "POST",
            body: body,
            bearerToken: activationToken
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
            "action": "handoffCreate",
            "handoffId": handoffID.uuidString,
            "jobId": sourceJobID,
            "summary": summary,
            "detail": detail,
            "urgency": urgency,
            "materialEstimate": materialEstimate
        ])
        _ = try await request(
            path: "/functions/nativeFieldMobile",
            method: "POST",
            body: body,
            bearerToken: activationToken
        )
    }

    func uploadProof(
        metadata: ProofMetadata,
        bytes: Data,
        activationToken: String
    ) async throws {
        var object: [String: Any] = [
            "action": "proofUpload",
            "proofId": metadata.proofID,
            "jobId": metadata.jobID,
            "phase": metadata.phase.lowercased() == "after" ? "after" : "before",
            "imageBase64": bytes.base64EncodedString(),
            "capturedAt": metadata.capturedAt
        ]
        if let lat = metadata.latitude { object["lat"] = lat }
        if let lng = metadata.longitude { object["lng"] = lng }
        if let accuracy = metadata.horizontalAccuracy { object["accuracy"] = accuracy }
        let body = try JSONSerialization.data(withJSONObject: object)
        _ = try await request(
            path: "/functions/nativeFieldMobile",
            method: "POST",
            body: body,
            bearerToken: activationToken
        )
    }

    func fetchMessages(activationToken: String) async throws -> [HaloMessage] {
        let body = try JSONSerialization.data(withJSONObject: ["action": "messagesList"])
        let data = try await request(
            path: "/functions/nativeFieldMobile",
            method: "POST",
            body: body,
            bearerToken: activationToken
        )
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = root["messages"] as? [[String: Any]]
        else { throw HaloAPIError.malformedPayload }

        return rows.compactMap { row in
            guard let id = Self.string(row["id"]) else { return nil }
            return HaloMessage(
                id: id,
                channel: Self.string(row["channel"]) ?? "field_dispatch",
                threadName: Self.string(row["threadName"]),
                from: Self.string(row["from"]) ?? "office",
                author: Self.string(row["author"]) ?? "Office",
                text: Self.string(row["text"]) ?? "",
                unitID: Self.string(row["unitId"]),
                unitLabel: Self.string(row["unitLabel"]),
                at: Self.string(row["at"]),
                read: (row["read"] as? Bool) ?? false,
                attachments: Self.messageAttachments(row["attachments"])
            )
        }
    }

    func sendMessage(
        text: String,
        jobID: String?,
        channel: String? = nil,
        activationToken: String
    ) async throws {
        var object: [String: Any] = ["action": "messageSend", "text": text]
        if let jobID, !jobID.isEmpty { object["jobId"] = jobID }
        if let channel, !channel.isEmpty { object["channel"] = channel }
        let body = try JSONSerialization.data(withJSONObject: object)
        _ = try await request(
            path: "/functions/nativeFieldMobile",
            method: "POST",
            body: body,
            bearerToken: activationToken
        )
    }

    func askGrok(
        message: String,
        jobID: String?,
        history: [HaloGrokTurn],
        activationToken: String
    ) async throws -> HaloGrokReply {
        var object: [String: Any] = [
            "action": "grokChat",
            "message": message,
            "history": history.suffix(12).map { [
                "role": $0.role == "assistant" ? "assistant" : "user",
                "content": $0.content
            ] }
        ]
        if let jobID, !jobID.isEmpty { object["jobId"] = jobID }

        let body = try JSONSerialization.data(withJSONObject: object)
        let data = try await request(
            path: "/functions/nativeFieldMobile",
            method: "POST",
            body: body,
            bearerToken: activationToken
        )

        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            (root["ok"] as? Bool) == true,
            let reply = Self.string(root["reply"]),
            !reply.isEmpty
        else {
            throw HaloAPIError.malformedPayload
        }

        return HaloGrokReply(
            reply: reply,
            model: Self.string(root["model"]) ?? "grok-4.6",
            groundedAt: Self.string(root["groundedAt"])
        )
    }

    func fetchGPSSessions(activationToken: String) async throws -> [HaloGPSSession] {
        let body = try JSONSerialization.data(withJSONObject: ["action": "gpsSessions"])
        let data = try await request(
            path: "/functions/nativeFieldMobile",
            method: "POST",
            body: body,
            bearerToken: activationToken
        )
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = root["sessions"] as? [[String: Any]]
        else { throw HaloAPIError.malformedPayload }

        return rows.compactMap { row in
            guard let id = Self.string(row["id"]), let token = Self.string(row["token"]) else { return nil }
            return HaloGPSSession(
                id: id,
                token: token,
                unitID: Self.string(row["unitId"]),
                property: Self.string(row["property"]),
                unitNumber: Self.string(row["unitNumber"]),
                active: (row["active"] as? Bool) ?? false,
                latitude: Self.double(row["lat"]),
                longitude: Self.double(row["lng"]),
                accuracy: Self.double(row["accuracy"]),
                capturedAt: Self.string(row["capturedAt"]),
                consentedAt: Self.string(row["consentedAt"]),
                expiresAt: Self.string(row["expiresAt"])
            )
        }
    }

    func updateGPSSession(id: String, location: CLLocation, activationToken: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "action": "gpsUpdate",
            "sessionId": id,
            "lat": location.coordinate.latitude,
            "lng": location.coordinate.longitude,
            "accuracy": location.horizontalAccuracy,
            "capturedAt": ISO8601DateFormatter().string(from: location.timestamp)
        ])
        _ = try await request(
            path: "/functions/nativeFieldMobile",
            method: "POST",
            body: body,
            bearerToken: activationToken
        )
    }

    func stopGPSSession(id: String, activationToken: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "action": "gpsStop",
            "sessionId": id
        ])
        _ = try await request(
            path: "/functions/nativeFieldMobile",
            method: "POST",
            body: body,
            bearerToken: activationToken
        )
    }

    func registerNativeDevice(
        deviceToken: String,
        activationToken: String
    ) async throws {
#if DEBUG
        let environment = "sandbox"
#else
        let environment = "production"
#endif
        let bundleID = Bundle.main.bundleIdentifier ?? "com.archangel.halofield"
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        let body = try JSONSerialization.data(withJSONObject: [
            "action": "registerDevice",
            "deviceToken": deviceToken,
            "environment": environment,
            "bundleId": bundleID,
            "appVersion": appVersion,
            "osVersion": osVersion
        ])
        _ = try await request(
            path: "/functions/nativeFieldMobile",
            method: "POST",
            body: body,
            bearerToken: activationToken
        )
    }

    func unregisterNativeDevice(
        deviceToken: String,
        activationToken: String
    ) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "action": "unregisterDevice",
            "deviceToken": deviceToken
        ])
        _ = try await request(
            path: "/functions/nativeFieldMobile",
            method: "POST",
            body: body,
            bearerToken: activationToken
        )
    }

    func fetchClockStatus(activationToken: String) async throws -> HaloClockStatus {
        let body = try JSONSerialization.data(withJSONObject: ["action": "clockStatus"])
        let data = try await request(
            path: "/functions/nativeFieldMobile",
            method: "POST",
            body: body,
            bearerToken: activationToken
        )

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HaloAPIError.malformedPayload
        }

        let configured = (root["configured"] as? Bool) ?? false
        let employeeID = Self.string(root["employeeId"])
        let entry: HaloClockEntry? = {
            guard let row = root["entry"] as? [String: Any],
                  let id = Self.string(row["id"]) else { return nil }
            return HaloClockEntry(
                id: id,
                jobID: Self.string(row["jobId"]),
                property: Self.string(row["property"]),
                unitNumber: Self.string(row["unitNumber"]),
                running: (row["running"] as? Bool) ?? false,
                status: Self.string(row["status"]) ?? "working",
                reviewStatus: Self.string(row["reviewStatus"]) ?? "",
                startedAt: Self.string(row["startedAt"]),
                workedMs: Self.int(row["workedMs"]) ?? 0,
                pauseReason: Self.string(row["pauseReason"]),
                sessionType: Self.string(row["sessionType"]) ?? "unit_work"
            )
        }()

        return HaloClockStatus(configured: configured, employeeID: employeeID, entry: entry)
    }

    func punchClock(
        kind: String,
        jobID: String,
        imageData: Data,
        location: CLLocation,
        requestID: UUID,
        activationToken: String
    ) async throws -> HaloClockEntry {
        let body = try JSONSerialization.data(withJSONObject: [
            "action": "clockPunch",
            "kind": kind,
            "jobId": jobID,
            "imageBase64": imageData.base64EncodedString(),
            "lat": location.coordinate.latitude,
            "lng": location.coordinate.longitude,
            "accuracy": location.horizontalAccuracy,
            "capturedAt": ISO8601DateFormatter().string(from: location.timestamp),
            "requestId": requestID.uuidString
        ])

        let data = try await request(
            path: "/functions/nativeFieldMobile",
            method: "POST",
            body: body,
            bearerToken: activationToken
        )
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entryID = Self.string(root["entryId"]) else {
            throw HaloAPIError.malformedPayload
        }

        return HaloClockEntry(
            id: entryID,
            jobID: jobID,
            property: nil,
            unitNumber: nil,
            running: kind == "start" || kind == "resume",
            status: Self.string(root["status"]) ?? (kind == "submit" ? "closed" : "working"),
            reviewStatus: Self.string(root["reviewStatus"]) ?? "",
            startedAt: nil,
            workedMs: Self.int(root["workedMs"]) ?? 0,
            pauseReason: kind == "pause" ? "break" : nil,
            sessionType: "unit_work"
        )
    }

    func toggleRework(
        jobID: String,
        index: Int,
        checked: Bool,
        activationToken: String
    ) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "action": "reworkToggle",
            "jobId": jobID,
            "index": index,
            "checked": checked
        ])
        _ = try await request(
            path: "/functions/nativeFieldMobile",
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
        var object: [String: Any] = [
            "id": id.uuidString,
            "jobId": jobID,
            "action": kind
        ]
        for (key, value) in payload {
            object[key] = value
        }
        let body = try JSONSerialization.data(withJSONObject: object)
        _ = try await request(
            path: "/functions/nativeFieldMobile",
            method: "POST",
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
        request.setValue("6aa4569d140d940e1d779ace", forHTTPHeaderField: "X-App-Id")
        if let bearerToken, !bearerToken.isEmpty {
            request.setValue(bearerToken, forHTTPHeaderField: "X-Halo-Activation")
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
                let message = Self.serverMessage(data, response: http) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
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
            beforePhotoCount: int(row["beforePhotoCount"]) ?? 0,
            afterPhotoCount: int(row["afterPhotoCount"]) ?? 0,
            flaggedCount: int(row["flaggedCount"]) ?? (rawStatus == "hold" || rawStatus == "flagged" ? 1 : 0),
            updatedAt: string(row["updatedAt"]) ?? string(row["createdAt"]),
            needsRework: (row["rework"] as? Bool) ?? false,
            reworkNotes: string(row["reworkNotes"]),
            reworkItems: reworkArray(row["reworkItems"]),
            closeoutStage: string(row["closeoutStage"]),
            closeoutBlockers: stringArray(row["closeoutBlockers"]),
            finalWalkAt: string(row["finalWalkAt"]),
            readyForWalk: (row["readyForWalk"] as? Bool) ?? false,
            walkVerified: (row["walkVerified"] as? Bool) ?? false
        )
    }

    nonisolated private static func mapState(status: String, boardStatus: String) -> JobState {
        switch status {
        case "complete", "completed", "paid", "cleared": return .complete
        case "hold", "flagged", "cancelled", "canceled": return .hold
        case "enroute", "en_route": return .enRoute
        case "arrived": return .arrived
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

    nonisolated private static func messageAttachments(_ value: Any?) -> [HaloMessageAttachment] {
        guard let rows = value as? [[String: Any]] else { return [] }
        return rows.enumerated().map { index, row in
            let snapshot = row["snapshot"] as? [String: Any]
            return HaloMessageAttachment(
                id: string(row["url"]) ?? string(row["name"]) ?? "attachment-\(index)",
                kind: string(row["kind"]) ?? "file",
                url: string(row["url"]),
                name: string(row["name"]),
                caption: string(row["caption"]),
                title: string(snapshot?["title"]) ?? string(row["name"]),
                status: string(snapshot?["status"]) ?? string(snapshot?["stage"]),
                actionTitle: string(snapshot?["action_title"]),
                actionSummary: string(snapshot?["action_summary"]),
                beforeURL: string(snapshot?["before_url"]),
                afterURL: string(snapshot?["after_url"]),
                proofPairs: proofPairs(snapshot?["pairs"])
            )
        }
    }

    nonisolated private static func proofPairs(_ value: Any?) -> [HaloProofPair] {
        guard let rows = value as? [[String: Any]] else { return [] }
        return rows.enumerated().map { index, row in
            HaloProofPair(
                id: "\(index)-\(string(row["area"]) ?? string(row["service"]) ?? "proof")",
                area: string(row["area"]) ?? string(row["service"]),
                beforeURL: string(row["before"]) ?? string(row["before_url"]),
                afterURL: string(row["after"]) ?? string(row["after_url"])
            )
        }
    }

    nonisolated private static func reworkArray(_ value: Any?) -> [ReworkItem] {
        guard let items = value as? [[String: Any]] else { return [] }
        return items.compactMap { row in
            guard
                let id = string(row["id"]),
                let index = int(row["index"]),
                let text = string(row["text"])
            else { return nil }
            return ReworkItem(
                id: id,
                index: index,
                text: text,
                isComplete: (row["checked"] as? Bool) ?? false
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

    nonisolated private static func serverMessage(_ data: Data, response: HTTPURLResponse) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["error", "message", "detail"] {
                if let message = json[key] as? String, !message.isEmpty { return message }
            }
        }

        // Do not show raw HTML or response headers that might contain credentials.
        let page = String(decoding: data.prefix(32_768), as: UTF8.self).lowercased()
        if response.statusCode == 403 && page.contains("cloudflare") && page.contains("access denied") {
            let ray = response.value(forHTTPHeaderField: "CF-Ray") ?? "unavailable"
            let safeRay = String(ray.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }.prefix(80))
            return "Base44's security gateway blocked this request. Activation could not be verified. Reference: \(safeRay)."
        }
        return nil
    }
}
