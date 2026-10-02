import CoreLocation
import Foundation

struct HaloMapGeofence: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let radiusMeters: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    static func valid(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180
            && !(latitude == 0 && longitude == 0)
    }
    func assessment(for crew: HaloManagerCrewLocation, now: Date) -> HaloFenceStatus {
        guard crew.displayState(at: now) == "live", let coordinate = crew.mapCoordinate(at: now),
              let accuracy = crew.accuracy, accuracy.isFinite, accuracy >= 0, accuracy <= 150 else { return .unavailable }
        let distance = CLLocation(latitude: latitude, longitude: longitude).distance(from:
            CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
        if distance + accuracy <= radiusMeters { return .inside }
        if distance - accuracy > radiusMeters { return .outside }
        return .boundary
    }
}

enum HaloFenceStatus: String {
    case inside = "Inside geofence"
    case outside = "Outside geofence"
    case boundary = "Near boundary"
    case unavailable = "Fresh precise GPS needed"
}

extension HaloManagerCrewLocation {
    var capturedDate: Date? {
        guard let capturedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: capturedAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: capturedAt)
    }
    func displayState(at now: Date) -> String {
        guard locationState == "live" || locationState.hasPrefix("recent") else { return locationState }
        guard let date = capturedDate else { return "location_unavailable" }
        let age = now.timeIntervalSince(date)
        guard age >= -30, age <= 900 else { return "expired" }
        if locationState == "live" && age > 120 { return "recent" }
        return locationState
    }
    func mapCoordinate(at now: Date) -> CLLocationCoordinate2D? {
        let state = displayState(at: now)
        guard state == "live" || state.hasPrefix("recent"),
              let latitude, let longitude, HaloMapGeofence.valid(latitude: latitude, longitude: longitude) else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }
    var initials: String { crewName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased() }
}
