import XCTest
@testable import HaloField

final class HaloTemplatePublishingTests: XCTestCase {
    private var validLayout: HaloWorkflowBlocks.Layout {
        .init(schemaVersion: 1, templateID: "fleet-dispatch",
              templateVersion: 1, tenantID: "fleet-a", industryID: "transport",
              blocks: [.init(id: "assign", kind: .assignment,
                             title: "Dispatch", order: 0, required: true,
                             visibleToRoles: ["dispatcher"], config: [:])])
    }

    func testPrepareRetainsRevisionAndIdempotencyKey() {
        let key = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let result = HaloTemplatePublishing.prepare(
            layout: validLayout, expectedRevision: 7, actorID: "admin-1", requestID: key)
        XCTAssertEqual(result, .success(.init(requestID: key,
                                              expectedRevision: 7, layout: validLayout)))
    }

    func testRejectsNegativeRevision() {
        let result = HaloTemplatePublishing.prepare(
            layout: validLayout, expectedRevision: -1, actorID: "admin-1", requestID: UUID())
        XCTAssertEqual(result, .failure(.invalidRevision))
    }

    func testRejectsRevisionBeyondJavaScriptSafeInteger() {
        let result = HaloTemplatePublishing.prepare(
            layout: validLayout, expectedRevision: Int.max, actorID: "admin-1", requestID: UUID())
        XCTAssertEqual(result, .failure(.invalidRevision))
    }

    func testRejectsRevisionThatWouldOverflowSafeNextRevision() {
        let maxSafe = 9_007_199_254_740_991
        let rejected = HaloTemplatePublishing.prepare(
            layout: validLayout, expectedRevision: maxSafe, actorID: "admin-1", requestID: UUID())
        XCTAssertEqual(rejected, .failure(.invalidRevision))
        let accepted = HaloTemplatePublishing.prepare(
            layout: validLayout, expectedRevision: maxSafe - 1, actorID: "admin-1", requestID: UUID())
        guard case .success = accepted else { return XCTFail("Expected last safe next revision") }
    }

    func testRejectsAnonymousActor() {
        let result = HaloTemplatePublishing.prepare(
            layout: validLayout, expectedRevision: 0, actorID: "  ", requestID: UUID())
        XCTAssertEqual(result, .failure(.invalidActor))
    }

    func testProposalJSONRoundTrip() throws {
        let result = HaloTemplatePublishing.prepare(
            layout: validLayout, expectedRevision: 0, actorID: "admin", requestID: UUID())
        guard case let .success(proposal) = result else { return XCTFail("Expected valid proposal") }
        let decoded = try JSONDecoder().decode(HaloTemplatePublishing.Proposal.self,
                                                from: JSONEncoder().encode(proposal))
        XCTAssertEqual(decoded, proposal)
    }
}
