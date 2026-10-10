import XCTest
@testable import HaloField

final class HaloTemplatePublishRecoveryStoreTests: XCTestCase {
    func testRecoverySurvivesStoreRecreationWithExactProposalAndNoToken() async throws {
        let fileURL = temporaryStoreURL()
        let detectedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let firstStore = HaloTemplatePublishRecoveryStore(fileURL: fileURL)
        let coordinator = HaloTemplatePublishCoordinator(
            recoveryStore: firstStore,
            now: { detectedAt },
            publishOperation: { _, _ in
                let recordsBeforeTransportCompletes = try await firstStore.records()
                XCTAssertEqual(recordsBeforeTransportCompletes.map(\.originalProposal), [self.proposal])
                throw HaloStagingWorkflowClient.Failure.commitOutcomeUnknown
            }
        )

        let outcome = try await coordinator.publish(
            proposal: proposal,
            bearerToken: "must-not-be-persisted"
        )

        let expected = HaloTemplatePublishing.UncertainPublish(
            originalProposal: proposal,
            detectedAt: detectedAt
        )
        XCTAssertEqual(outcome, .recoveryRequired(expected))

        // Simulate process termination by constructing a new actor from disk.
        let restoredStore = HaloTemplatePublishRecoveryStore(fileURL: fileURL)
        let restored = try await restoredStore.records()
        XCTAssertEqual(restored, [expected])
        XCTAssertFalse(
            String(decoding: try Data(contentsOf: fileURL), as: UTF8.self)
                .contains("must-not-be-persisted")
        )
    }

    func testExistingRecoveryPreventsASecondPublishAttempt() async throws {
        let store = HaloTemplatePublishRecoveryStore(fileURL: temporaryStoreURL())
        let existing = HaloTemplatePublishing.UncertainPublish(
            originalProposal: proposal,
            detectedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try await store.save(existing)
        let spy = PublishSpy(error: .commitOutcomeUnknown)
        let coordinator = HaloTemplatePublishCoordinator(
            recoveryStore: store,
            publishOperation: { proposal, token in
                try await spy.publish(proposal: proposal, token: token)
            }
        )

        let outcome = try await coordinator.publish(proposal: proposal, bearerToken: "token")

        let calls = await spy.calls
        XCTAssertEqual(outcome, .recoveryRequired(existing))
        XCTAssertEqual(calls, 0, "A persisted uncertain request must reconcile, never republish")
    }

    func testVerifiedPublishRemovesPreflightRecoveryRecord() async throws {
        let store = HaloTemplatePublishRecoveryStore(fileURL: temporaryStoreURL())
        let receipt = HaloStagingWorkflowClient.Receipt(
            templateID: proposal.layout.templateID,
            revision: proposal.expectedRevision + 1,
            templateVersion: proposal.layout.templateVersion
        )
        let coordinator = HaloTemplatePublishCoordinator(
            recoveryStore: store,
            publishOperation: { _, _ in receipt }
        )

        let outcome = try await coordinator.publish(proposal: proposal, bearerToken: "token")

        let records = try await store.records()
        XCTAssertEqual(outcome, .published(receipt))
        XCTAssertEqual(records, [])
    }

    func testSameRequestIDCannotReplacePersistedOriginalProposal() async throws {
        let store = HaloTemplatePublishRecoveryStore(fileURL: temporaryStoreURL())
        let original = HaloTemplatePublishing.UncertainPublish(
            originalProposal: proposal,
            detectedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try await store.save(original)

        let altered = HaloTemplatePublishing.UncertainPublish(
            originalProposal: .init(
                requestID: proposal.requestID,
                expectedRevision: proposal.expectedRevision + 1,
                layout: proposal.layout
            ),
            detectedAt: original.detectedAt.addingTimeInterval(1)
        )

        do {
            try await store.save(altered)
            XCTFail("A recovery ID must never be rebound to another revision")
        } catch let error as HaloTemplatePublishRecoveryStore.Failure {
            XCTAssertEqual(error, .requestIdentityConflict)
        }
        let records = try await store.records()
        XCTAssertEqual(records, [original])
    }

    func testTerminalConflictIsNotRecordedOrRetried() async throws {
        let store = HaloTemplatePublishRecoveryStore(fileURL: temporaryStoreURL())
        let spy = PublishSpy(error: .revisionConflict)
        let coordinator = HaloTemplatePublishCoordinator(
            recoveryStore: store,
            publishOperation: { proposal, token in
                try await spy.publish(proposal: proposal, token: token)
            }
        )

        do {
            _ = try await coordinator.publish(proposal: proposal, bearerToken: "token")
            XCTFail("A revision conflict must remain terminal")
        } catch let error as HaloStagingWorkflowClient.Failure {
            XCTAssertEqual(error, .revisionConflict)
        }
        let calls = await spy.calls
        let records = try await store.records()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(records, [])
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

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("halo-recovery-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("uncertain-publishes.json")
    }
}

private actor PublishSpy {
    private(set) var calls = 0
    let error: HaloStagingWorkflowClient.Failure

    init(error: HaloStagingWorkflowClient.Failure) {
        self.error = error
    }

    func publish(
        proposal: HaloTemplatePublishing.Proposal,
        token: String
    ) throws -> HaloStagingWorkflowClient.Receipt {
        calls += 1
        throw error
    }
}
