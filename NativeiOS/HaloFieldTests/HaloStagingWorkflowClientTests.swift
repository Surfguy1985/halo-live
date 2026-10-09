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
        return .init(requestID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
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
            let body = try JSONDecoder().decode(HaloTemplatePublishing.Proposal.self,
                                                from: try XCTUnwrap(request.httpBody))
            XCTAssertEqual(body, expected)
        }
        let receipt = try await client.publish(proposal: expected, bearerToken: "staging-test-token")
        XCTAssertEqual(receipt.revision, 8)
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
