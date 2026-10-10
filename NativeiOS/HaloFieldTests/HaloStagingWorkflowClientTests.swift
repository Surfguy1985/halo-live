import Foundation
import XCTest
@testable import HaloField

final class HaloStagingWorkflowClientTests: XCTestCase {
    private let staging = URL(string: "https://staging.example.test")!

    private var proposal: HaloTemplatePublishing.Proposal {
        let layout = HaloWorkflowBlocks.Layout(
            schemaVersion: 1, templateID: "fleet-dispatch", templateVersion: 1,
            tenantID: "fleet-a", industryID: "transport",
            blocks: [.init(id: "assign", kind: .assignment, title: "Dispatch",
                           order: 0, required: true, visibleToRoles: ["dispatcher"], config: [:])]
        )
        return .init(requestID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
                     expectedRevision: 7, layout: layout)
    }

    func testRejectsProductionAndBase44Endpoints() {
        for raw in ["https://api.halo.example", "https://halo-back-office-copy-1d779ace.base44.app",
                    "http://staging.example.test", "https://staging.example.test/other"] {
            XCTAssertThrowsError(try HaloStagingWorkflowClient(stagingURL: URL(string: raw)!))
        }
    }

    func testSendsAuthenticatedRevisionAndIdempotencyProposal() async throws {
        let expected = proposal
        let client = try makeClient(status: 200,
            payload: #"{"templateID":"fleet-dispatch","revision":8,"templateVersion":1}"#) { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/workflow-templates/fleet-dispatch/publish")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer staging-test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), expected.requestID.uuidString)
            // URLSession can surface uploaded JSON as httpBodyStream in URLProtocol.
            let payload: Data
            if let direct = request.httpBody {
                payload = direct
            } else if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count < 0 { throw XCTBodyReadError.streamFailure }
                    if count == 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
                payload = data
            } else {
                throw XCTBodyReadError.missingBody
            }
            let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
            XCTAssertEqual(raw["requestID"] as? String,
                           request.value(forHTTPHeaderField: "Idempotency-Key"))
            let body = try JSONDecoder().decode(HaloTemplatePublishing.Proposal.self, from: payload)
            XCTAssertEqual(body, expected)
        }
        let receipt = try await client.publish(proposal: expected, bearerToken: "staging-test-token")
        XCTAssertEqual(receipt.revision, 8)
    }

    func testRejectsSuccessReceiptWithUnexpectedRevision() async throws {
        for revision in [7, 9, 999] {
            let client = try makeClient(status: 200,
                payload: "{\"templateID\":\"fleet-dispatch\",\"revision\":\(revision),\"templateVersion\":1}")
            do {
                _ = try await client.publish(proposal: proposal, bearerToken: "staging-test-token")
                XCTFail("Must not accept receipt revision \(revision) for expected revision 7")
            } catch let error as HaloStagingWorkflowClient.Failure {
                XCTAssertEqual(error, .invalidResponse)
            }
        }
    }

    func testRejectsUnsafeRevisionBeforeNetworkRequest() async throws {
        var calls = 0
        let client = try makeClient(status: 200,
            payload: #"{"templateID":"fleet-dispatch","revision":8,"templateVersion":1}"#) { _ in
            calls += 1
        }
        let invalid = HaloTemplatePublishing.Proposal(
            requestID: UUID(), expectedRevision: Int.max, layout: proposal.layout)
        do {
            _ = try await client.publish(proposal: invalid, bearerToken: "staging-test-token")
            XCTFail("Unsafe revision must be rejected before transport")
        } catch let error as HaloStagingWorkflowClient.Failure {
            XCTAssertEqual(error, .invalidSchema)
        }
        XCTAssertEqual(calls, 0)
    }

    func testRejectsRevisionWhoseNextValueWouldBeUnsafeBeforeNetworkRequest() async throws {
        var calls = 0
        let client = try makeClient(status: 200,
            payload: #"{"templateID":"fleet-dispatch","revision":8,"templateVersion":1}"#) { _ in
            calls += 1
        }
        let invalid = HaloTemplatePublishing.Proposal(
            requestID: UUID(), expectedRevision: 9_007_199_254_740_991, layout: proposal.layout)
        do {
            _ = try await client.publish(proposal: invalid, bearerToken: "staging-test-token")
            XCTFail("Next revision would be unsafe")
        } catch let error as HaloStagingWorkflowClient.Failure {
            XCTAssertEqual(error, .invalidSchema)
        }
        XCTAssertEqual(calls, 0)
    }

    func testRejectsRevisionConflictWithoutAutomaticRetry() async throws {
        let client = try makeClient(status: 409, payload: #"{"error":"REVISION_CONFLICT"}"#)
        do {
            _ = try await client.publish(proposal: proposal, bearerToken: "staging-test-token")
            XCTFail("Must not silently overwrite revision")
        } catch let error as HaloStagingWorkflowClient.Failure {
            XCTAssertEqual(error, .revisionConflict)
        }
    }

    func testUncertainCommitRequiresOriginalRequestIDReconciliation() async throws {
        var calls = 0
        let client = try makeClient(status: 503,
            payload: #"{"error":"COMMIT_OUTCOME_UNKNOWN"}"#) { _ in calls += 1 }
        do {
            _ = try await client.publish(proposal: proposal, bearerToken: "staging-test-token")
            XCTFail("Uncertain commit cannot be reported as successful")
        } catch let error as HaloStagingWorkflowClient.Failure {
            XCTAssertEqual(error, .commitOutcomeUnknown)
        }
        XCTAssertEqual(calls, 1, "Do not automatically replay a potentially committed mutation")
    }

    func testExplicitReconciliationIsReadOnlyAndPreservesOriginalRequestID() async throws {
        var calls = 0
        let original = proposal
        let client = try makeClient(status: 200,
            payload: #"{"status":"committed","receipt":{"templateID":"fleet-dispatch","revision":8,"templateVersion":1}}"#) { request in
            calls += 1
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"),
                           original.requestID.uuidString)
            XCTAssertEqual(request.url?.path,
                           "/v1/workflow-templates/fleet-dispatch/reconcile")
            // The recovery payload must contain only the original request ID,
            // not a mutable workflow layout or a new publish attempt.
            if let body = request.httpBody {
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(object.count, 1)
                XCTAssertEqual(object["requestID"] as? String, original.requestID.uuidString)
            }
        }
        let receipt = try await client.reconcileUncertainPublish(
            originalProposal: original, bearerToken: "staging-test-token")
        XCTAssertEqual(receipt.revision, original.expectedRevision + 1)
        XCTAssertEqual(calls, 1)
    }

    func testMissingReconciliationReceiptDoesNotTriggerRepublish() async throws {
        var calls = 0
        let client = try makeClient(status: 404, payload: #"{"error":"RECEIPT_NOT_FOUND"}"#) { request in
            calls += 1
            XCTAssertEqual(request.url?.path, "/v1/workflow-templates/fleet-dispatch/reconcile")
        }
        do {
            _ = try await client.reconcileUncertainPublish(
                originalProposal: proposal, bearerToken: "staging-test-token")
            XCTFail("Missing receipt is not proof that the original commit rolled back")
        } catch let error as HaloStagingWorkflowClient.Failure {
            XCTAssertEqual(error, .receiptNotFound)
        }
        XCTAssertEqual(calls, 1)
    }

    func testReconciliationRejectsUntrustedReceiptRevision() async throws {
        let client = try makeClient(status: 200,
            payload: #"{"status":"committed","receipt":{"templateID":"fleet-dispatch","revision":9,"templateVersion":1}}"#)
        do {
            _ = try await client.reconcileUncertainPublish(
                originalProposal: proposal, bearerToken: "staging-test-token")
            XCTFail("Recovery cannot accept a receipt for another revision")
        } catch let error as HaloStagingWorkflowClient.Failure {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testReconciliationDoesNotRetryOnServiceUnavailable() async throws {
        var calls = 0
        let client = try makeClient(status: 503, payload: #"{"error":"SERVICE_UNAVAILABLE"}"#) { request in
            calls += 1
            XCTAssertEqual(request.url?.path, "/v1/workflow-templates/fleet-dispatch/reconcile")
        }
        do {
            _ = try await client.reconcileUncertainPublish(
                originalProposal: proposal, bearerToken: "staging-test-token")
            XCTFail("A transient error must not be reported as a recovered commit")
        } catch let error as HaloStagingWorkflowClient.Failure {
            XCTAssertEqual(error, .serviceUnavailable)
        }
        XCTAssertEqual(calls, 1, "No hidden retry or second publish")
    }

    func testReconciliationRejectsRevokedMembership() async throws {
        var calls = 0
        let client = try makeClient(status: 403, payload: #"{"error":"FORBIDDEN"}"#) { request in
            calls += 1
            XCTAssertEqual(request.url?.path, "/v1/workflow-templates/fleet-dispatch/reconcile")
        }
        do {
            _ = try await client.reconcileUncertainPublish(
                originalProposal: proposal, bearerToken: "staging-test-token")
            XCTFail("Revoked membership cannot recover a receipt")
        } catch let error as HaloStagingWorkflowClient.Failure {
            XCTAssertEqual(error, .forbidden)
        }
        XCTAssertEqual(calls, 1)
    }

    func testReconciliationRejectsInvalidCredentialsWithoutNetwork() async throws {
        var calls = 0
        let client = try makeClient(status: 200,
            payload: #"{"status":"committed","receipt":{"templateID":"fleet-dispatch","revision":8,"templateVersion":1}}"#) { _ in
            calls += 1
        }
        do {
            _ = try await client.reconcileUncertainPublish(
                originalProposal: proposal, bearerToken: "bad token")
            XCTFail("Invalid credentials must fail locally")
        } catch let error as HaloStagingWorkflowClient.Failure {
            XCTAssertEqual(error, .invalidCredentials)
        }
        XCTAssertEqual(calls, 0)
    }

    func testLostNetworkReceiptRecoversReadOnlyWithoutSecondPublish() async throws {
        let original = proposal
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StagingWorkflowURLProtocol.self]
        var publishCalls = 0
        var reconcileCalls = 0
        StagingWorkflowURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"),
                           original.requestID.uuidString)
            let path = request.url?.path
            if path == "/v1/workflow-templates/fleet-dispatch/publish" {
                publishCalls += 1
                // Simulate a response lost after the server may have committed.
                throw URLError(.networkConnectionLost)
            }
            XCTAssertEqual(path, "/v1/workflow-templates/fleet-dispatch/reconcile")
            reconcileCalls += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                           httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            let body = #"{"status":"committed","receipt":{"templateID":"fleet-dispatch","revision":8,"templateVersion":1}}"#
            return (response, Data(body.utf8))
        }
        let client = try HaloStagingWorkflowClient(stagingURL: staging,
            session: URLSession(configuration: configuration))
        do {
            _ = try await client.publish(proposal: original, bearerToken: "staging-test-token")
            XCTFail("A dropped response must not be reported as a successful publish")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .networkConnectionLost)
        }
        let recovered = try await client.reconcileUncertainPublish(
            originalProposal: original, bearerToken: "staging-test-token")
        XCTAssertEqual(recovered.revision, original.expectedRevision + 1)
        XCTAssertEqual(publishCalls, 1, "Network failure must not cause another mutation")
        XCTAssertEqual(reconcileCalls, 1, "Recovery must use the read-only endpoint")
    }

    func testRejectsIdempotencyConflict() async throws {
        let client = try makeClient(status: 409, payload: #"{"error":"IDEMPOTENCY_CONFLICT"}"#)
        do {
            _ = try await client.publish(proposal: proposal, bearerToken: "staging-test-token")
            XCTFail("Must not replay conflicted request")
        } catch let error as HaloStagingWorkflowClient.Failure {
            XCTAssertEqual(error, .idempotencyConflict)
        }
    }

    func testUnauthorizedDoesNotFallBackToBase44() async throws {
        let client = try makeClient(status: 401, payload: #"{"error":"UNAUTHENTICATED"}"#)
        do {
            _ = try await client.publish(proposal: proposal, bearerToken: "staging-test-token")
            XCTFail("Must not succeed without verified identity")
        } catch let error as HaloStagingWorkflowClient.Failure {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func testRejectsUnexpectedSuccessPayload() async throws {
        let client = try makeClient(status: 200, payload: #"{"revision":8}"#)
        do {
            _ = try await client.publish(proposal: proposal, bearerToken: "staging-test-token")
            XCTFail("Must reject incomplete receipt")
        } catch let error as HaloStagingWorkflowClient.Failure {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testForbiddenIsNotRetriedOrDowngraded() async throws {
        var calls = 0
        let client = try makeClient(status: 403, payload: #"{"error":"FORBIDDEN"}"#) { _ in
            calls += 1
        }
        do {
            _ = try await client.publish(proposal: proposal, bearerToken: "staging-test-token")
            XCTFail("Publish should reject revoked membership")
        } catch let error as HaloStagingWorkflowClient.Failure {
            XCTAssertEqual(error, .forbidden)
        }
        XCTAssertEqual(calls, 1, "Authorization failures must never auto-retry")
    }

    func testServerValidationErrorIsPreserved() async throws {
        let client = try makeClient(status: 422, payload: #"{"error":"INVALID_REQUEST"}"#)
        do {
            _ = try await client.publish(proposal: proposal, bearerToken: "staging-test-token")
            XCTFail("Server validation is authoritative")
        } catch let error as HaloStagingWorkflowClient.Failure {
            XCTAssertEqual(error, .invalidSchema)
        }
    }

    func testRateLimitIsNotAutomaticallyRetried() async throws {
        var calls = 0
        let client = try makeClient(status: 429, payload: #"{"error":"RATE_LIMITED"}"#) { _ in
            calls += 1
        }
        do {
            _ = try await client.publish(proposal: proposal, bearerToken: "staging-test-token")
            XCTFail("Must not silently replay a rate-limited mutation")
        } catch let error as HaloStagingWorkflowClient.Failure {
            XCTAssertEqual(error, .serviceUnavailable)
        }
        XCTAssertEqual(calls, 1)
    }

    func testHTTPRedirectCannotBeTreatedAsSuccessfulPublish() async throws {
        let client = try makeClient(status: 302, payload: "") { request in
            XCTAssertEqual(request.url?.host, "staging.example.test")
        }
        do {
            _ = try await client.publish(proposal: proposal, bearerToken: "staging-test-token")
            XCTFail("Redirect is not a publishing receipt")
        } catch let error as HaloStagingWorkflowClient.Failure {
            XCTAssertEqual(error, .unexpectedStatus(302))
        }
    }

    func testInvalidCredentialsFailBeforeAnyNetworkRequest() async throws {
        var calls = 0
        let client = try makeClient(status: 200,
            payload: #"{"templateID":"fleet-dispatch","revision":8,"templateVersion":1}"#) { _ in
            calls += 1
        }
        for invalid in ["", "has spaces", "contains\nnewline"] {
            do {
                _ = try await client.publish(proposal: proposal, bearerToken: invalid)
                XCTFail("Invalid bearer token must be rejected")
            } catch let error as HaloStagingWorkflowClient.Failure {
                XCTAssertEqual(error, .invalidCredentials)
            }
        }
        XCTAssertEqual(calls, 0)
    }

    private func makeClient(
        status: Int, payload: String,
        inspect: @escaping (URLRequest) throws -> Void = { _ in }
    ) throws -> HaloStagingWorkflowClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StagingWorkflowURLProtocol.self]
        StagingWorkflowURLProtocol.handler = { request in
            try inspect(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (response, Data(payload.utf8))
        }
        return try HaloStagingWorkflowClient(stagingURL: staging,
                                             session: URLSession(configuration: configuration))
    }
}

private final class StagingWorkflowURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

private enum XCTBodyReadError: Error {
    case missingBody
    case streamFailure
}
