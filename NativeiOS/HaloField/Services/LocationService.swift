import CoreLocation
import Foundation

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var errorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .otherNavigation
    }

    func requestPermission() { manager.requestWhenInUseAuthorization() }
    func refresh() {
        errorMessage = nil
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.requestLocation()
    }

    var hasLocationPermission: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var isDeniedOrRestricted: Bool {
        authorization == .denied || authorization == .restricted
    }

    func freshLocation(maxAge: TimeInterval = 120, requiredAccuracy: CLLocationAccuracy = 100) -> CLLocation? {
        guard let location else { return nil }
        guard abs(location.timestamp.timeIntervalSinceNow) <= maxAge else { return nil }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= requiredAccuracy else { return nil }
        return location
    }

    func startJobTracking() {
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 25
        manager.startUpdatingLocation()
    }

    func stopJobTracking() { manager.stopUpdatingLocation() }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in authorization = manager.authorizationStatus }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in location = latest; errorMessage = nil }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in errorMessage = error.localizedDescription }
    }
}