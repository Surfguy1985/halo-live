import XCTest
@testable import HaloField

final class HaloMarketplaceClientTests: XCTestCase {
    func testNativeMarketplaceRequiresHTTPSOrigin() {
        XCTAssertThrowsError(
            try HaloMarketplaceAPIClient(
                apiOrigin: URL(string: "http://api.halo.example")!,
                getAccessToken: { "unused-test-token" }
            )
        )
        XCTAssertThrowsError(
            try HaloMarketplaceAPIClient(
                apiOrigin: URL(string: "https://user:pass@api.halo.example")!,
                getAccessToken: { "unused-test-token" }
            )
        )
        XCTAssertThrowsError(
            try HaloMarketplaceAPIClient(
                apiOrigin: URL(string: "https://api.halo.example/tenant/other")!,
                getAccessToken: { "unused-test-token" }
            )
        )
    }

    func testPreviewJobCannotTriggerAPrepareOrRequestNetworkCall() async throws {
        let client = try HaloMarketplaceAPIClient(
            apiOrigin: URL(string: "https://api.halo.example")!,
            getAccessToken: {
                XCTFail("Preview must fail before requesting a login credential")
                return "never-contact-auth"
            }
        )
        let job = HaloMarketplacePreview.opportunities[0]
        do {
            _ = try await client.prepare(job)
            XCTFail("Preview should not prepare an actual job request")
        } catch HaloMarketplaceNetworkError.rejected {
            // Intentional: no client-auth or HTTP traffic for preview data.
        }

        let fabricated = HaloMarketplacePreparedAttempt(
            opportunityID: job.id,
            publisherOrganizationID: job.publisherOrganizationID,
            originalKey: "test_original_key_12345678901",
            reservedNow: true,
            receipt: nil
        )
        do {
            _ = try await client.submitFirstRequest(job, prepared: fabricated)
            XCTFail("Preview must not submit a request")
        } catch HaloMarketplaceNetworkError.rejected {
            // Expected.
        }
    }

    func testReusingAnExistingReservationNeverIssuesAnotherJobPost() async throws {
        let client = try HaloMarketplaceAPIClient(
            apiOrigin: URL(string: "https://api.halo.example")!,
            getAccessToken: {
                XCTFail("A previously reserved job must not call the credential provider")
                return "unused-token"
            }
        )
        let sample = HaloMarketplacePreview.opportunities[0]
        let liveShapedJob = HaloMarketplaceOpportunity(
            id: "0199e37f-1234-7123-8123-0123456789ab",
            publisherOrganizationID: "0199e37f-1234-7123-8123-0123456789ac",
            title: sample.title,
            industry: sample.industry,
            locality: sample.locality,
            latitude: sample.latitude,
            longitude: sample.longitude,
            compensationMinor: sample.compensationMinor,
            customerName: sample.customerName,
            customerVerified: false,
            scope: sample.scope,
            scheduledStart: sample.scheduledStart,
            durationMinutes: sample.durationMinutes,
            mediaURLs: [],
            previewOnly: false
        )
        let previous = HaloMarketplacePreparedAttempt(
            opportunityID: liveShapedJob.id,
            publisherOrganizationID: liveShapedJob.publisherOrganizationID,
            originalKey: "same_original_key_12345678901",
            reservedNow: false,
            receipt: nil
        )
        do {
            _ = try await client.submitFirstRequest(liveShapedJob, prepared: previous)
            XCTFail("Previously reserved attempt must never submit again")
        } catch HaloMarketplaceNetworkError.rejected {
            // Expected without a network call.
        }
    }
}
