import Foundation

/// Explicitly configured staging-only transport for enterprise workflow publishing.
/// Not referenced by HaloAPI, live Base44, or any application view.
struct HaloStagingWorkflowClient {
    enum Failure: Error, Equatable {
        case invalidStagingURL
        case invalidCredentials
        case invalidTemplateID
        case unauthorized
        case forbidden
        case revisionConflict
        case idempotencyConflict
        case publishRequestNotFound
        case invalidSchema
        case serviceUnavailable
        case commitOutcomeUnknown
        case unexpectedStatus(Int)
        case invalidResponse
    }

    struct Receipt: Decodable, Equatable {
        let templateID: String
        let revision: Int
        let templateVersion: Int
    }

    private let baseURL: URL
    private let session: URLSession

    init(stagingURL: URL, session: URLSession = .shared) throws {
        guard stagingURL.scheme?.lowercased() == "https",
              let host = stagingURL.host?.lowercased(),
              host.split(separator: ".").contains(where: { $0 == "staging" || $0 == "stage" }),
              stagingURL.user == nil, stagingURL.password == nil,
              stagingURL.query == nil, stagingURL.fragment == nil,
              stagingURL.path.isEmpty || stagingURL.path == "/" else {
            throw Failure.invalidStagingURL
        }
        self.baseURL = stagingURL
        self.session = session
    }

    func publish(
        proposal: HaloTemplatePublishing.Proposal,
        bearerToken: String
    ) async throws -> Receipt {
        let request = try request(
            operation: "publish",
            proposal: proposal,
            bearerToken: bearerToken
        )

        // Never forward bearer credentials to another host through an HTTP redirect.
        let (data, response) = try await session.data(for: request, delegate: NoRedirects())
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        switch http.statusCode {
        case 200:
            return try validatedReceipt(data: data, proposal: proposal)
        case 401: throw Failure.unauthorized
        case 403: throw Failure.forbidden
        case 409:
            let code = (try? JSONDecoder().decode(ErrorPayload.self, from: data))?.error
            if code == "IDEMPOTENCY_CONFLICT" { throw Failure.idempotencyConflict }
            if code == "REVISION_CONFLICT" { throw Failure.revisionConflict }
            throw Failure.invalidResponse
        case 422: throw Failure.invalidSchema
        case 503:
            let code = (try? JSONDecoder().decode(ErrorPayload.self, from: data))?.error
            if code == "COMMIT_OUTCOME_UNKNOWN" { throw Failure.commitOutcomeUnknown }
            throw Failure.serviceUnavailable
        case 429, 502, 504: throw Failure.serviceUnavailable
        default: throw Failure.unexpectedStatus(http.statusCode)
        }
    }

    /// Explicit, read-only reconciliation after COMMIT_OUTCOME_UNKNOWN or a lost
    /// HTTP receipt. The caller MUST persist and supply the original proposal.
    /// This never falls back to /publish, constructs a new UUID, or changes the
    /// expected revision.
    func reconcileUncertainPublish(
        originalProposal: HaloTemplatePublishing.Proposal,
        bearerToken: String
    ) async throws -> Receipt {
        let request = try request(
            operation: "reconcile",
            proposal: originalProposal,
            bearerToken: bearerToken
        )
        let (data, response) = try await session.data(for: request, delegate: NoRedirects())
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        switch http.statusCode {
        case 200:
            guard let envelope = try? JSONDecoder().decode(ReconciliationReceipt.self, from: data),
                  envelope.requestID == originalProposal.requestID,
                  envelope.outcome == "COMMITTED" else {
                throw Failure.invalidResponse
            }
            return try validatedReceipt(envelope.result, proposal: originalProposal)
        case 401: throw Failure.unauthorized
        case 403: throw Failure.forbidden
        case 404:
            let code = (try? JSONDecoder().decode(ErrorPayload.self, from: data))?.error
            guard code == "PUBLISH_REQUEST_NOT_FOUND" else { throw Failure.invalidResponse }
            throw Failure.publishRequestNotFound
        case 409:
            let code = (try? JSONDecoder().decode(ErrorPayload.self, from: data))?.error
            guard code == "IDEMPOTENCY_CONFLICT" else { throw Failure.invalidResponse }
            throw Failure.idempotencyConflict
        case 422: throw Failure.invalidSchema
        case 429, 500, 502, 503, 504: throw Failure.serviceUnavailable
        default: throw Failure.unexpectedStatus(http.statusCode)
        }
    }

    private func request(
        operation: String,
        proposal: HaloTemplatePublishing.Proposal,
        bearerToken: String
    ) throws -> URLRequest {
        guard !bearerToken.isEmpty,
              bearerToken.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw Failure.invalidCredentials
        }
        let templateID = proposal.layout.templateID
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        guard !templateID.isEmpty, templateID.utf8.count <= 128,
              templateID.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw Failure.invalidTemplateID
        }
        guard proposal.expectedRevision >= 0,
              proposal.expectedRevision < 9_007_199_254_740_991,
              case .success = HaloWorkflowBlocks.validate(proposal.layout) else {
            throw Failure.invalidSchema
        }

        let endpoint = baseURL.appendingPathComponent(
            "v1/workflow-templates/\(templateID)/\(operation)"
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue(proposal.requestID.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try JSONEncoder().encode(proposal)
        return request
    }

    private func validatedReceipt(
        data: Data,
        proposal: HaloTemplatePublishing.Proposal
    ) throws -> Receipt {
        guard let receipt = try? JSONDecoder().decode(Receipt.self, from: data) else {
            throw Failure.invalidResponse
        }
        return try validatedReceipt(receipt, proposal: proposal)
    }

    private func validatedReceipt(
        _ receipt: Receipt,
        proposal: HaloTemplatePublishing.Proposal
    ) throws -> Receipt {
        guard receipt.templateID == proposal.layout.templateID,
              receipt.revision == proposal.expectedRevision + 1,
              receipt.templateVersion == proposal.layout.templateVersion else {
            throw Failure.invalidResponse
        }
        return receipt
    }

    private struct ReconciliationReceipt: Decodable {
        let requestID: UUID
        let outcome: String
        let result: Receipt
    }

    private struct ErrorPayload: Decodable {
        let error: String
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
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
}
