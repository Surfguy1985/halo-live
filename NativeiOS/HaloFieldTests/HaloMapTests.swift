import XCTest
@testable import HaloField

final class HaloMapTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var fence: HaloMapGeofence {
        HaloMapGeofence(id: "property", name: "Property", address: "", latitude: 33, longitude: -96, radiusMeters: 300)
    }
    private func crew(latitude: Double = 33, accuracy: Double = 10, age: Double = 0, state: String = "live") -> HaloManagerCrewLocation {
        HaloManagerCrewLocation(id: "crew", crewID: "crew", crewName: "Field Crew", photoURL: nil,
            identityVerifiedToday: false, property: "Property", unitID: "unit", unitNumber: "2418",
            services: [], status: "checked_in", locationState: state, freshness: "live", latitude: latitude,
            longitude: -96, accuracy: accuracy, capturedAt: ISO8601DateFormatter().string(from: now.addingTimeInterval(-age)), workedMs: 0)
    }
    func testLiveGPSAgesOutWithoutAnotherNetworkResponse() {
        XCTAssertEqual(crew(age: 60).displayState(at: now), "live")
        XCTAssertEqual(crew(age: 121).displayState(at: now), "recent")
        XCTAssertEqual(crew(age: 901).displayState(at: now), "expired")
        XCTAssertNil(crew(age: 901).mapCoordinate(at: now))
        XCTAssertNil(crew(age: -60).mapCoordinate(at: now))
        XCTAssertNil(crew(state: "sharing_stopped").mapCoordinate(at: now))
    }
    func testGeofenceAccountsForGPSUncertainty() {
        XCTAssertEqual(fence.assessment(for: crew(), now: now), .inside)
        XCTAssertEqual(fence.assessment(for: crew(latitude: 33.01), now: now), .outside)
        XCTAssertEqual(fence.assessment(for: crew(latitude: 33.003, accuracy: 100), now: now), .boundary)
        XCTAssertEqual(fence.assessment(for: crew(accuracy: 200), now: now), .unavailable)
        XCTAssertEqual(fence.assessment(for: crew(accuracy: -1), now: now), .unavailable)
        XCTAssertEqual(fence.assessment(for: crew(age: 121), now: now), .unavailable)
        XCTAssertEqual(fence.assessment(for: crew(state: "recent_verified"), now: now), .unavailable)
    }
    func testNearbyBubblesGroupAndStaleCrewsStayOffMap() {
        let groups = HaloCrewCluster.group([crew(), crew(latitude: 33.0001), crew(latitude: 33.01), crew(age: 901)], at: now)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map { $0.crews.count }.sorted(), [1, 2])
    }
    func testInvalidCoordinatesNeverBecomeMapPins() {
        XCTAssertNil(crew(latitude: 100).mapCoordinate(at: now))
        XCTAssertFalse(HaloMapGeofence.valid(latitude: .nan, longitude: -96))
        XCTAssertFalse(HaloMapGeofence.valid(latitude: 0, longitude: 0))
        XCTAssertFalse(HaloMapGeofence.valid(latitude: 33, longitude: .infinity))
    }
}
