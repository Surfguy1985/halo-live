import XCTest
@testable import HaloField

@MainActor
final class HaloTemplatePublishRecoveryTests: XCTestCase {
    func testUncertainPublishRoundTripPreservesOriginalRecoveryIdentity() throws {
        let original = proposal
        let uncertain = HaloTemplatePublishing.UncertainPublish(
            originalProposal: original,
            detectedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let decoded = try JSONDecoder().decode(
            HaloTemplatePublishing.UncertainPublish.self,
            from: JSONEncoder().encode(uncertain)
        )

        XCTAssertEqual(decoded, uncertain)
        XCTAssertEqual(decoded.id, original.requestID)
        XCTAssertEqual(decoded.originalProposal.expectedRevision, original.expectedRevision)
    }

    func testRecoveryWaitsForExplicitUserActionAndReusesOriginalProposal() async {
        let spy = RecoveryReconcilerSpy(responses: [.success(receipt)])
        let recovery = makeRecovery(spy: spy)

        XCTAssertEqual(recovery.state, .awaitingUserAction)
        let callsBeforeAction = await spy.callCount
        XCTAssertEqual(callsBeforeAction, 0)

        await recovery.checkPublishOutcome()

        XCTAssertEqual(recovery.state, .published(receipt))
        let callsAfterAction = await spy.callCount
        let sentProposals = await spy.proposals
        let sentTokens = await spy.tokens
        XCTAssertEqual(callsAfterAction, 1)
        XCTAssertEqual(sentProposals, [proposal])
        XCTAssertEqual(sentTokens, ["staging-token"])
    }

    func testUnknownOutcomeNeedsAnotherExplicitActionAndStillReusesOriginalProposal() async {
        let spy = RecoveryReconcilerSpy(responses: [
            .failure(.commitOutcomeUnknown),
            .success(receipt),
        ])
        let recovery = makeRecovery(spy: spy)

        await recovery.checkPublishOutcome()

        XCTAssertEqual(recovery.state, .retryAvailable(.outcomeStillUnknown))
        let callsAfterFirstAction = await spy.callCount
        XCTAssertEqual(callsAfterFirstAction, 1, "Recovery must never retry itself")

        await recovery.checkPublishOutcome()

        XCTAssertEqual(recovery.state, .published(receipt))
        let sentProposals = await spy.proposals
        XCTAssertEqual(sentProposals, [proposal, proposal])
    }

    func testConflictStopsFurtherReplayAndRequiresReview() async {
        let spy = RecoveryReconcilerSpy(responses: [.failure(.revisionConflict)])
        let recovery = makeRecovery(spy: spy)

        await recovery.checkPublishOutcome()
        await recovery.checkPublishOutcome()

        XCTAssertEqual(recovery.state, .needsAttention(.revisionConflict))
        XCTAssertFalse(recovery.canCheckOutcome)
        let calls = await spy.callCount
        XCTAssertEqual(calls, 1)
    }

    func testMissingReceiptOnlyAllowsAnotherExplicitReconciliation() async {
        let spy = RecoveryReconcilerSpy(responses: [
            .failure(.publishRequestNotFound),
            .success(receipt),
        ])
        let recovery = makeRecovery(spy: spy)

        await recovery.checkPublishOutcome()

        XCTAssertEqual(recovery.state, .retryAvailable(.publishRequestNotFound))
        XCTAssertTrue(recovery.canCheckOutcome)
        let callsAfterMissingReceipt = await spy.callCount
        XCTAssertEqual(callsAfterMissingReceipt, 1, "A missing receipt must not trigger a publish or retry")

        await recovery.checkPublishOutcome()

        let proposals = await spy.proposals
        XCTAssertEqual(recovery.state, .published(receipt))
        XCTAssertEqual(proposals, [proposal, proposal])
    }

    func testMissingCredentialDoesNotSendRecoveryRequest() async {
        let spy = RecoveryReconcilerSpy(responses: [.success(receipt)])
        let recovery = HaloTemplatePublishRecovery(
            uncertainPublish: uncertainPublish,
            bearerToken: { nil },
            reconcileOperation: { proposal, token in
                try await spy.reconcile(proposal: proposal, token: token)
            }
        )

        await recovery.checkPublishOutcome()

        XCTAssertEqual(recovery.state, .needsAttention(.authenticationRequired))
        XCTAssertTrue(recovery.canCheckOutcome, "A restored session may safely check the same request")
        let calls = await spy.callCount
        XCTAssertEqual(calls, 0)
    }

    private var proposal: HaloTemplatePublishing.Proposal {
        .init(
            requestID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            expectedRevision: 7,
            layout: .init(
                schemaVersion: 1,
                templateID: "fleet-dispatch",
                templateVersion: 1,
                tenantID: "fleet-a",
                industryID: "transport",
                blocks: [
                    .init(
                        id: "assign",
                        kind: .assignment,
                        title: "Dispatch",
                        order: 0,
                        required: true,
                        visibleToRoles: ["dispatcher"],
                        config: [:]
                    ),
                ]
            )
        )
    }

    private var uncertainPublish: HaloTemplatePublishing.UncertainPublish {
        .init(originalProposal: proposal, detectedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    private var receipt: HaloStagingWorkflowClient.Receipt {
        .init(templateID: "fleet-dispatch", revision: 8, templateVersion: 1)
    }

    private func makeRecovery(spy: RecoveryReconcilerSpy) -> HaloTemplatePublishRecovery {
        HaloTemplatePublishRecovery(
            uncertainPublish: uncertainPublish,
            bearerToken: { "staging-token" },
            reconcileOperation: { proposal, token in
                try await spy.reconcile(proposal: proposal, token: token)
            }
        )
    }
}

private actor RecoveryReconcilerSpy {
    enum Response {
        case success(HaloStagingWorkflowClient.Receipt)
        case failure(HaloStagingWorkflowClient.Failure)
    }

    private(set) var proposals: [HaloTemplatePublishing.Proposal] = []
    private(set) var tokens: [String] = []
    private var responses: [Response]

    init(responses: [Response]) {
        self.responses = responses
    }

    var callCount: Int { proposals.count }

    func reconcile(
        proposal: HaloTemplatePublishing.Proposal,
        token: String
    ) throws -> HaloStagingWorkflowClient.Receipt {
        proposals.append(proposal)
        tokens.append(token)
        switch responses.removeFirst() {
        case let .success(receipt): return receipt
        case let .failure(failure): throw failure
        }
    }
}
