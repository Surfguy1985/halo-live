import XCTest
@testable import HaloField

final class HaloWorkflowKernelTests: XCTestCase {
    private let template = HaloWorkflowKernel.Template(
        id: "turn-v1", version: 1, tenantID: "property-a", industryID: "property",
        initialState: "assigned", terminalStates: ["closed"],
        transitions: [
            .init(id: "complete", fromState: "assigned", toState: "review",
                  allowedRoles: ["crew"], requiredEvidenceKeys: ["after-photo"]),
            .init(id: "approve", fromState: "review", toState: "closed",
                  allowedRoles: ["manager"], requiredEvidenceKeys: ["signed-approval"])
        ]
    )

    private var item: HaloWorkflowKernel.WorkItem {
        .init(id: "job-1", tenantID: "property-a", industryID: "property",
              templateID: "turn-v1", templateVersion: 1, state: "assigned")
    }

    private func context(tenant: String = "property-a",
                         industry: String = "property",
                         roles: Set<String> = ["crew"],
                         evidence: Set<String> = ["after-photo"]) -> HaloWorkflowKernel.Context {
        .init(tenantID: tenant, industryID: industry,
              actorID: "worker-1", roles: roles, evidenceKeys: evidence)
    }

    func testValidEvidenceBackedTransition() {
        XCTAssertTrue(HaloWorkflowKernel.validate(template))
        XCTAssertEqual(HaloWorkflowKernel.evaluate(
            template: template, item: item, transitionID: "complete", context: context()
        ), .success("review"))
    }

    func testTenantIsolation() {
        XCTAssertEqual(HaloWorkflowKernel.evaluate(
            template: template, item: item, transitionID: "complete",
            context: context(tenant: "property-b")
        ), .failure(.tenantMismatch))
    }

    func testIndustryIsolation() {
        XCTAssertEqual(HaloWorkflowKernel.evaluate(
            template: template, item: item, transitionID: "complete",
            context: context(industry: "transport")
        ), .failure(.industryMismatch))
    }

    func testRoleRestrictions() {
        XCTAssertEqual(HaloWorkflowKernel.evaluate(
            template: template, item: item, transitionID: "complete",
            context: context(roles: ["manager"])
        ), .failure(.forbidden))
    }

    func testMissingEvidence() {
        XCTAssertEqual(HaloWorkflowKernel.evaluate(
            template: template, item: item, transitionID: "complete",
            context: context(evidence: [])
        ), .failure(.missingEvidence(["after-photo"])))
    }

    func testUnknownTransitionAndWrongState() {
        XCTAssertEqual(HaloWorkflowKernel.evaluate(
            template: template, item: item, transitionID: "approve", context: context()
        ), .failure(.invalidTransition))
    }

    func testVersionPinning() {
        let upgraded = HaloWorkflowKernel.Template(
            id: template.id, version: 2, tenantID: template.tenantID,
            industryID: template.industryID, initialState: template.initialState,
            terminalStates: template.terminalStates, transitions: template.transitions
        )
        XCTAssertEqual(HaloWorkflowKernel.evaluate(
            template: upgraded, item: item, transitionID: "complete", context: context()
        ), .failure(.templateMismatch))
    }

    func testTerminalStateCannotMove() {
        let closed = HaloWorkflowKernel.WorkItem(
            id: item.id, tenantID: item.tenantID, industryID: item.industryID,
            templateID: item.templateID, templateVersion: item.templateVersion, state: "closed"
        )
        XCTAssertEqual(HaloWorkflowKernel.evaluate(
            template: template, item: closed, transitionID: "complete", context: context()
        ), .failure(.terminalState))
    }

    func testRejectMalformedTemplate() {
        let invalid = HaloWorkflowKernel.Template(
            id: template.id, version: template.version, tenantID: template.tenantID,
            industryID: template.industryID, initialState: template.initialState,
            terminalStates: template.terminalStates,
            transitions: template.transitions + [template.transitions[0]]
        )
        XCTAssertFalse(HaloWorkflowKernel.validate(invalid))
    }
}
