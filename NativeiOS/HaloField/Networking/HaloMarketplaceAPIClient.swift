import Foundation

enum HaloMarketplaceNetworkError: LocalizedError {
    case invalidConfiguration
    case unauthenticated
    case rejected
    case invalidResponse
    case unavailable
    case outcomeUnknown

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "HALO marketplace requires a reviewed HTTPS endpoint."
        case .unauthenticated: "Sign in with a verified marketplace account."
        case .rejected: "The marketplace request was rejected."
        case .invalidResponse: "HALO returned an unexpected marketplace response."
        case .unavailable: "Marketplace service is unavailable."
        case .outcomeUnknown: "The request may have succeeded. Recover its original status before trying again."
        }
    }
}

struct HaloMarketplaceReceipt: Equatable, Sendable {
    let opportunityID: String
    let publisherOrganizationID: String
    let requestID: String
    let state: String
}

struct HaloMarketplacePreparedAttempt: Sendable {
    let opportunityID: String
    let publisherOrganizationID: String
    let originalKey: String
    let reservedNow: Bool
    let receipt: HaloMarketplaceReceipt?
}

/// Block URLSession redirects so an Authorization header can never be
/// forwarded to a destination controlled by a redirecting host.
private final class HaloMarketplaceNoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Xcode-native HALO opportunity contract. NOT connected to production.
/// Never pass HaloSessionStore.activationToken: Back Office activation is not a
/// trusted signed JWT for the separate HALO opportunity service.
actor HaloMarketplaceAPIClient {
    typealias AccessTokenProvider = @Sendable () async throws -> String

    private let origin: URL
    private let accessToken: AccessTokenProvider
    private let session: URLSession

    init(apiOrigin: URL, getAccessToken: @escaping AccessTokenProvider) throws {
        guard apiOrigin.scheme == "https",
              apiOrigin.host != nil,
              apiOrigin.user == nil, apiOrigin.password == nil,
              apiOrigin.query == nil, apiOrigin.fragment == nil,
              apiOrigin.path.isEmpty || apiOrigin.path == "/" else {
            throw HaloMarketplaceNetworkError.invalidConfiguration
        }
        self.origin = apiOrigin
        self.accessToken = getAccessToken
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(
            configuration: configuration,
            delegate: HaloMarketplaceNoRedirects(),
            delegateQueue: nil
        )
    }

    // Network responses never supply preview/demo records as fallbacks.
    func list() async throws -> [HaloMarketplaceOpportunity] {
        let data = try await send(method: "GET", path: "/v1/marketplace/opportunities")
        let payload = try envelope(data)
        guard let rows = payload["items"] as? [[String: Any]],
              rows.count <= 100 else {
            throw HaloMarketplaceNetworkError.invalidResponse
        }
        let items = try rows.map(parseJob)
        guard Set(items.map(\.id)).count == items.count else {
            throw HaloMarketplaceNetworkError.invalidResponse
        }
        return items
    }

    /// Durable server reservation occurs BEFORE any attempt to apply for work.
    /// Existing cross-device reservations always return their original key.
    func prepare(_ job: HaloMarketplaceOpportunity) async throws -> HaloMarketplacePreparedAttempt {
        guard !job.previewOnly else { throw HaloMarketplaceNetworkError.rejected }
        let payload = try envelope(try await send(
            method: "POST", path: "/v1/marketplace/requests/prepare",
            body: parameters(job), uncertainOnFailure: true
        ))
        guard payload["opportunityId"] as? String == job.id,
              payload["publisherOrganizationId"] as? String == job.publisherOrganizationID,
              let key = payload["idempotencyKey"] as? String, Self.validKey(key),
              let reservedNow = payload["reservedNow"] as? Bool,
              let status = payload["state"] as? String else {
            throw HaloMarketplaceNetworkError.outcomeUnknown
        }

        let receipt: HaloMarketplaceReceipt?
        if status == "submitted" {
            guard !reservedNow, let source = payload["receipt"] as? [String: Any] else {
                throw HaloMarketplaceNetworkError.outcomeUnknown
            }
            receipt = try parseReceipt(source, job: job)
        } else if status == "unconfirmed", payload["receipt"] == nil {
            receipt = nil
        } else {
            throw HaloMarketplaceNetworkError.outcomeUnknown
        }
        return HaloMarketplacePreparedAttempt(
            opportunityID: job.id,
            publisherOrganizationID: job.publisherOrganizationID,
            originalKey: key,
            reservedNow: reservedNow,
            receipt: receipt
        )
    }

    /// Only a FIRST, newly reserved request can be submitted. A previous
    /// reservation must be reconciled; it cannot generate another POST.
    func submitFirstRequest(
        _ job: HaloMarketplaceOpportunity,
        prepared: HaloMarketplacePreparedAttempt
    ) async throws -> HaloMarketplaceReceipt {
        guard !job.previewOnly, prepared.reservedNow, prepared.receipt == nil,
              prepared.opportunityID == job.id,
              prepared.publisherOrganizationID == job.publisherOrganizationID,
              Self.validKey(prepared.originalKey) else {
            throw HaloMarketplaceNetworkError.rejected
        }
        let body = try envelope(try await send(
            method: "POST",
            path: "/v1/marketplace/opportunities/\(job.id)/requests",
            body: parameters(job),
            idempotencyKey: prepared.originalKey,
            uncertainOnFailure: true
        ))
        return try parseReceipt(body, job: job)
    }

    /// Read-only original-key receipt lookup after an uncertain POST. A 404 is
    /// not evidence that a previous request failed or that a retry is safe.
    func reconcile(
        _ job: HaloMarketplaceOpportunity,
        originalKey: String
    ) async throws -> HaloMarketplaceReceipt? {
        guard !job.previewOnly, Self.validKey(originalKey) else {
            throw HaloMarketplaceNetworkError.invalidConfiguration
        }
        guard let data = try await send(
            method: "POST", path: "/v1/marketplace/requests/reconcile",
            body: parameters(job), idempotencyKey: originalKey,
            allowMissingReceipt: true
        ) else { return nil }
        return try parseReceipt(envelope(data), job: job)
    }

    private func parameters(_ job: HaloMarketplaceOpportunity) -> [String: String] {
        ["opportunityId": job.id, "publisherOrganizationId": job.publisherOrganizationID]
    }

    private func send(
        method: String,
        path: String,
        body: [String: String]? = nil,
        idempotencyKey: String? = nil,
        uncertainOnFailure: Bool = false,
        allowMissingReceipt: Bool = false
    ) async throws -> Data? {
        let token: String
        do { token = try await accessToken() }
        catch { throw HaloMarketplaceNetworkError.unauthenticated }
        guard !token.isEmpty, token.count <= 8_192,
              token.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil else {
            throw HaloMarketplaceNetworkError.unauthenticated
        }
        guard let endpoint = URL(string: path, relativeTo: origin)?.absoluteURL,
              endpoint.host == origin.host, endpoint.scheme == "https" else {
            throw HaloMarketplaceNetworkError.invalidConfiguration
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpShouldHandleCookies = false
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let idempotencyKey {
            guard Self.validKey(idempotencyKey) else {
                throw HaloMarketplaceNetworkError.invalidConfiguration
            }
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch {
            throw uncertainOnFailure
                ? HaloMarketplaceNetworkError.outcomeUnknown
                : HaloMarketplaceNetworkError.unavailable
        }
        guard let http = response as? HTTPURLResponse else {
            throw uncertainOnFailure
                ? HaloMarketplaceNetworkError.outcomeUnknown
                : HaloMarketplaceNetworkError.invalidResponse
        }
        if allowMissingReceipt && http.statusCode == 404 { return nil }
        guard (200...201).contains(http.statusCode) else {
            if http.statusCode == 401 { throw HaloMarketplaceNetworkError.unauthenticated }
            if [403, 404, 409, 422].contains(http.statusCode) {
                throw HaloMarketplaceNetworkError.rejected
            }
            throw uncertainOnFailure
                ? HaloMarketplaceNetworkError.outcomeUnknown
                : HaloMarketplaceNetworkError.unavailable
        }
        guard http.value(forHTTPHeaderField: "Content-Type")?
            .lowercased().hasPrefix("application/json") == true else {
            throw uncertainOnFailure
                ? HaloMarketplaceNetworkError.outcomeUnknown
                : HaloMarketplaceNetworkError.invalidResponse
        }
        return data
    }

    private func envelope(_ data: Data?) throws -> [String: Any] {
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["ok"] as? Bool == true,
              let requestID = root["requestId"] as? String, Self.validUUIDv7(requestID),
              let payload = root["data"] as? [String: Any] else {
            throw HaloMarketplaceNetworkError.invalidResponse
        }
        return payload
    }

    private func parseReceipt(
        _ payload: [String: Any],
        job: HaloMarketplaceOpportunity
    ) throws -> HaloMarketplaceReceipt {
        guard payload["opportunityId"] as? String == job.id,
              payload["publisherOrganizationId"] as? String == job.publisherOrganizationID,
              let requestID = payload["serverRequestId"] as? String,
              Self.validUUIDv7(requestID),
              let status = payload["state"] as? String,
              ["received", "pending_review"].contains(status) else {
            throw HaloMarketplaceNetworkError.invalidResponse
        }
        return HaloMarketplaceReceipt(
            opportunityID: job.id, publisherOrganizationID: job.publisherOrganizationID,
            requestID: requestID, state: status
        )
    }

    private func parseJob(_ item: [String: Any]) throws -> HaloMarketplaceOpportunity {
        guard let id = item["id"] as? String, Self.validUUIDv7(id),
              let publisher = item["publisherOrganizationId"] as? String,
              Self.validUUIDv7(publisher),
              item["visibility"] as? String == "marketplace",
              item["status"] as? String == "open",
              let title = item["title"] as? String, !title.trimmingCharacters(in: .whitespaces).isEmpty,
              title.count <= 180,
              let name = item["clientName"] as? String, !name.isEmpty,
              let verified = item["clientVerified"] as? Bool,
              let industryCode = item["industry"] as? String,
              let industry = HaloMarketplaceIndustry.allCases.first(where: {
                  $0 != .all && $0.apiValue == industryCode
              }),
              let locality = item["locality"] as? String, !locality.isEmpty,
              let location = item["location"] as? [String: Any],
              let latitude = location["latitude"] as? Double,
              let longitude = location["longitude"] as? Double,
              let price = item["price"] as? [String: Any],
              price["currency"] as? String == "USD",
              let minor = price["amountMinor"] as? Int, minor >= 0,
              minor <= 9_007_199_254_740_991,
              let duration = item["estimatedDurationMinutes"] as? Int,
              (1...10_080).contains(duration),
              let strings = item["requirements"] as? [String], strings.count <= 40,
              let media = item["media"] as? [String], media.count <= 12,
              let iso = item["scheduledStartISO"] as? String,
              let date = Self.parseISODate(iso) else {
            throw HaloMarketplaceNetworkError.invalidResponse
        }
        let urls = try media.map { string -> URL in
            guard let url = URL(string: string), url.scheme == "https",
                  url.user == nil, url.password == nil else {
                throw HaloMarketplaceNetworkError.invalidResponse
            }
            return url
        }
        let job = HaloMarketplaceOpportunity(
            id: id, publisherOrganizationID: publisher, title: title,
            industry: industry, locality: locality, latitude: latitude,
            longitude: longitude, compensationMinor: minor,
            customerName: name, customerVerified: verified,
            scope: strings, scheduledStart: date, durationMinutes: duration,
            mediaURLs: urls, previewOnly: false
        )
        guard job.validMapPosition else {
            throw HaloMarketplaceNetworkError.invalidResponse
        }
        return job
    }

    private static func parseISODate(_ string: String) -> Date? {
        guard string.hasSuffix("Z") ||
              string.range(of: #"[+-][0-9]{2}:[0-9]{2}$"#, options: .regularExpression) != nil else {
            return nil
        }
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = format.date(from: string) { return result }
        format.formatOptions = [.withInternetDateTime]
        return format.date(from: string)
    }

    private static func validUUIDv7(_ id: String) -> Bool {
        id.range(of:
            #"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#,
            options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func validKey(_ key: String) -> Bool {
        key.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]{15,127}$"#,
                  options: .regularExpression) != nil
    }
}
