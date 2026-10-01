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
        guard hasLocationPermission else {
            if authorization == .notDetermined {
                manager.requestWhenInUseAuthorization()
            }
            return
        }
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

    func startLiveSharing() {
        errorMessage = nil
        if authorization == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 20
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    func stopLiveSharing() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        manager.pausesLocationUpdatesAutomatically = true
        manager.distanceFilter = kCLDistanceFilterNone
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorization = manager.authorizationStatus
            if authorization == .authorizedWhenInUse || authorization == .authorizedAlways {
                self.manager.desiredAccuracy = kCLLocationAccuracyBest
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in location = latest; errorMessage = nil }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in errorMessage = error.localizedDescription }
    }
}