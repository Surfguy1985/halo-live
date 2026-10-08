import XCTest
@testable import HaloField

final class HaloWorkflowBlocksTests: XCTestCase {
    private var layout: HaloWorkflowBlocks.Layout {
        .init(schemaVersion: 1, templateID: "construction-job",
              templateVersion: 3, tenantID: "tenant-a", industryID: "construction",
              blocks: [
                .init(id: "approval", kind: .approval, title: "Approval", order: 2,
                      required: true, visibleToRoles: ["manager"], config: [:]),
                .init(id: "photos", kind: .photoProof, title: "Field proof", order: 1,
                      required: true, visibleToRoles: ["crew", "manager"], config: ["minPhotos": "1"]),
                .init(id: "assignment", kind: .assignment, title: "Assignment", order: 0,
                      required: true, visibleToRoles: ["crew", "manager"], config: [:])
              ])
    }

    func testValidLayoutAndRoleFilteredOrdering() {
        XCTAssertEqual(HaloWorkflowBlocks.validate(layout), .success(layout))
        XCTAssertEqual(HaloWorkflowBlocks.visibleBlocks(in: layout, roles: ["crew"]).map(\.id),
                       ["assignment", "photos"])
        XCTAssertEqual(HaloWorkflowBlocks.visibleBlocks(in: layout, roles: ["manager"]).map(\.id),
                       ["assignment", "photos", "approval"])
    }

    func testReorderPreservesBlockProperties() {
        let result = HaloWorkflowBlocks.reordered(layout, orderedIDs: ["approval", "photos", "assignment"])
        guard case let .success(updated) = result else { return XCTFail("Expected successful reorder") }
        XCTAssertEqual(updated.blocks.sorted(by: { $0.order < $1.order }).map(\.id),
                       ["approval", "photos", "assignment"])
        XCTAssertEqual(updated.blocks.first(where: { $0.id == "photos" })?.config["minPhotos"], "1")
        XCTAssertEqual(updated.templateVersion, 3)
    }

    func testReorderRejectsMissingAndDuplicateIDs() {
        XCTAssertEqual(HaloWorkflowBlocks.reordered(layout, orderedIDs: ["photos"]), .failure(.invalidBlock))
        XCTAssertEqual(HaloWorkflowBlocks.reordered(layout, orderedIDs: ["photos", "photos", "approval"]),
                       .failure(.invalidBlock))
    }

    func testRejectsDuplicateIDsAndOrders() {
        let duplicated = HaloWorkflowBlocks.Layout(
            schemaVersion: 1, templateID: layout.templateID, templateVersion: 3,
            tenantID: layout.tenantID, industryID: layout.industryID,
            blocks: layout.blocks + [layout.blocks[0]])
        XCTAssertEqual(HaloWorkflowBlocks.validate(duplicated), .failure(.duplicateBlockID))
        let clash = HaloWorkflowBlocks.Layout(
            schemaVersion: 1, templateID: layout.templateID, templateVersion: 3,
            tenantID: layout.tenantID, industryID: layout.industryID,
            blocks: Array(layout.blocks.prefix(2)) + [
                .init(id: "new", kind: .messaging, title: "Chat", order: 1,
                      required: false, visibleToRoles: ["crew"], config: [:])
            ])
        XCTAssertEqual(HaloWorkflowBlocks.validate(clash), .failure(.duplicateOrder))
    }

    func testRejectsUnsupportedSchema() {
        let newer = HaloWorkflowBlocks.Layout(
            schemaVersion: 99, templateID: layout.templateID, templateVersion: 3,
            tenantID: layout.tenantID, industryID: layout.industryID, blocks: layout.blocks)
        XCTAssertEqual(HaloWorkflowBlocks.validate(newer), .failure(.unsupportedSchema))
        XCTAssertTrue(HaloWorkflowBlocks.visibleBlocks(in: newer, roles: ["crew"]).isEmpty)
    }

    func testJSONRoundTrip() throws {
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(HaloWorkflowBlocks.Layout.self, from: data)
        XCTAssertEqual(decoded, layout)
    }
}
