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
        case invalidSchema
        case serviceUnavailable
        case commitOutcomeUnknown
        case receiptNotFound
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

        let endpoint = baseURL.appendingPathComponent("v1/workflow-templates/\(templateID)/publish")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue(proposal.requestID.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try JSONEncoder().encode(proposal)

        // Never forward bearer credentials to another host through an HTTP redirect.
        let (data, response) = try await session.data(for: request, delegate: NoRedirects())
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        switch http.statusCode {
        case 200:
            guard let receipt = try? JSONDecoder().decode(Receipt.self, from: data),
                  receipt.templateID == templateID,
                  receipt.revision == proposal.expectedRevision + 1,
                  receipt.templateVersion == proposal.layout.templateVersion else {
                throw Failure.invalidResponse
            }
            return receipt
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

    /// Read-only recovery for a potentially committed publish. Never issues a
    /// second mutation, changes the request ID, or treats 404 as rollback proof.
    /// The caller retains the original proposal if a receipt is not yet visible.
    func reconcileUncertainPublish(
        originalProposal: HaloTemplatePublishing.Proposal,
        bearerToken: String
    ) async throws -> Receipt {
        guard !bearerToken.isEmpty,
              bearerToken.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw Failure.invalidCredentials
        }
        let templateID = originalProposal.layout.templateID
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        guard !templateID.isEmpty, templateID.utf8.count <= 128,
              templateID.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw Failure.invalidTemplateID
        }
        guard originalProposal.expectedRevision >= 0,
              originalProposal.expectedRevision < 9_007_199_254_740_991,
              case .success = HaloWorkflowBlocks.validate(originalProposal.layout) else {
            throw Failure.invalidSchema
        }
        let endpoint = baseURL.appendingPathComponent("v1/workflow-templates/\(templateID)/reconcile")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue(originalProposal.requestID.uuidString, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try JSONEncoder().encode(ReconcileRequest(requestID: originalProposal.requestID))
        let (data, response) = try await session.data(for: request, delegate: NoRedirects())
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        switch http.statusCode {
        case 200:
            guard let envelope = try? JSONDecoder().decode(ReconcileEnvelope.self, from: data),
                  envelope.status == "committed",
                  envelope.receipt.templateID == templateID,
                  envelope.receipt.revision == originalProposal.expectedRevision + 1,
                  envelope.receipt.templateVersion == originalProposal.layout.templateVersion else {
                throw Failure.invalidResponse
            }
            return envelope.receipt
        case 401: throw Failure.unauthorized
        case 403: throw Failure.forbidden
        case 404: throw Failure.receiptNotFound
        case 422: throw Failure.invalidSchema
        case 429, 502, 503, 504: throw Failure.serviceUnavailable
        default: throw Failure.unexpectedStatus(http.statusCode)
        }
    }

    private struct ReconcileRequest: Encodable {
        let requestID: UUID
    }

    private struct ReconcileEnvelope: Decodable {
        let status: String
        let receipt: Receipt
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


/// Staging-only, opt-in durable record of a publish whose receipt is unresolved.
/// Persist BEFORE sending the publish. Delete only after a verified receipt.
/// No bearer token or identity credential is ever stored in this journal.
/// File protection is device-enforced on iOS; callers must supply a private
/// Application Support URL and an authenticated owner scope.
actor HaloStagingPublishRecoveryJournal {
    enum Failure: Error {
        case invalidScope
        case corruptRecord
        case wrongOwner
    }

    private struct Record: Codable {
        let ownerScope: String
        let proposal: HaloTemplatePublishing.Proposal
    }

    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func save(_ proposal: HaloTemplatePublishing.Proposal, ownerScope: String) throws {
        guard !ownerScope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.invalidScope
        }
        // Never overwrite an unresolved operation with a different request ID.
        if let existing = try pending(ownerScope: ownerScope), existing != proposal {
            throw Failure.corruptRecord
        }
        let manager = FileManager.default
        try manager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Record(ownerScope: ownerScope, proposal: proposal))
        #if os(iOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: fileURL, options: [.atomic])
        #endif
    }

    func pending(ownerScope: String) throws -> HaloTemplatePublishing.Proposal? {
        guard !ownerScope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.invalidScope
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        guard let record = try? JSONDecoder().decode(Record.self, from: data) else {
            throw Failure.corruptRecord
        }
        guard record.ownerScope == ownerScope else { throw Failure.wrongOwner }
        return record.proposal
    }

    func clear(confirmedRequestID: UUID, ownerScope: String) throws {
        guard let proposal = try pending(ownerScope: ownerScope) else { return }
        guard proposal.requestID == confirmedRequestID else { throw Failure.corruptRecord }
        try FileManager.default.removeItem(at: fileURL)
    }
}


/// Explicit staging coordinator. The host app supplies a verified owner scope,
/// current bearer credential and a private journal URL. No automatic background
/// retries, startup network calls or production integration.
actor HaloStagingPublishRecoveryCoordinator {
    private let client: HaloStagingWorkflowClient
    private let journal: HaloStagingPublishRecoveryJournal

    init(client: HaloStagingWorkflowClient, journal: HaloStagingPublishRecoveryJournal) {
        self.client = client
        self.journal = journal
    }

    /// Journal the original mutation before the first network attempt.
    /// An existing unresolved request cannot be replaced by another proposal.
    func publish(
        proposal: HaloTemplatePublishing.Proposal,
        ownerScope: String,
        bearerToken: String
    ) async throws -> HaloStagingWorkflowClient.Receipt {
        try await journal.save(proposal, ownerScope: ownerScope)
        let receipt = try await client.publish(proposal: proposal, bearerToken: bearerToken)
        try await journal.clear(confirmedRequestID: proposal.requestID, ownerScope: ownerScope)
        return receipt
    }

    /// Called explicitly after restart or an uncertain response, once the
    /// authenticated principal has been verified again by the host application.
    /// A 404, transport error, or revoked membership keeps the journal intact.
    func recover(
        ownerScope: String,
        bearerToken: String
    ) async throws -> HaloStagingWorkflowClient.Receipt? {
        guard let proposal = try await journal.pending(ownerScope: ownerScope) else { return nil }
        let receipt = try await client.reconcileUncertainPublish(
            originalProposal: proposal, bearerToken: bearerToken)
        try await journal.clear(confirmedRequestID: proposal.requestID, ownerScope: ownerScope)
        return receipt
    }
}
