import XCTest
@testable import HaloField

final class HaloMarketplaceTests: XCTestCase {
    func testFigmaIndustryFiltersWorkAcrossContractorCategories() {
        let all = HaloMarketplacePreview.opportunities
        XCTAssertEqual(all.count, 5)
        XCTAssertTrue(all.allSatisfy(\.previewOnly))

        var filter = HaloMarketplaceFilter()
        filter.industry = .construction
        XCTAssertEqual(filter.apply(to: all).map(\.id), ["demo-construction"])

        filter.industry = .transportation
        XCTAssertEqual(filter.apply(to: all).map(\.id), ["demo-delivery"])

        filter.industry = .all
        filter.query = "restaurant"
        XCTAssertEqual(filter.apply(to: all).map(\.id), ["demo-service"])
    }

    func testCompensationAndSavedFiltersNeverInventJobs() {
        let all = HaloMarketplacePreview.opportunities
        var filter = HaloMarketplaceFilter()
        filter.minimumCompensationMinor = 50_000
        XCTAssertEqual(Set(filter.apply(to: all).map(\.id)), Set(["demo-construction", "demo-service"]))
        filter.savedOnly = true
        XCTAssertTrue(filter.apply(to: all).isEmpty)
        filter.savedIDs = ["demo-service"]
        XCTAssertEqual(filter.apply(to: all).map(\.id), ["demo-service"])
    }

    func testIllustrativePayoutsNeverRepresentRealAssignments() {
        let first = HaloMarketplacePreview.opportunities[0]
        XCTAssertEqual(first.payout, "$420")
        XCTAssertEqual(first.publisherOrganizationID, "demo-publisher")
        XCTAssertFalse(first.customerVerified)
        XCTAssertTrue(first.previewOnly)
        XCTAssertTrue(first.validMapPosition)
    }

    func testMalformedCoordinatesFailClosedInMapFilters() {
        let job = HaloMarketplacePreview.opportunities[0]
        let invalid = HaloMarketplaceOpportunity(
            id: job.id, publisherOrganizationID: job.publisherOrganizationID,
            title: job.title, industry: job.industry, locality: job.locality,
            latitude: 200, longitude: job.longitude,
            compensationMinor: job.compensationMinor,
            customerName: job.customerName, customerVerified: false,
            scope: job.scope, scheduledStart: job.scheduledStart,
            durationMinutes: job.durationMinutes,
            mediaURLs: [], previewOnly: true
        )
        XCTAssertFalse(invalid.validMapPosition)
        XCTAssertTrue(HaloMarketplaceFilter().apply(to: [invalid]).isEmpty)
    }
}
