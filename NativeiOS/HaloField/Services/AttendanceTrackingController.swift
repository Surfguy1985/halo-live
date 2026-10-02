import Combine
import CoreLocation
import Foundation

@MainActor
final class AttendanceTrackingController: ObservableObject {
    @Published private(set) var isTracking = false
    @Published private(set) var sessionID: String?
    @Published private(set) var lastUploadedAt: Date?
    @Published private(set) var lastError: String?

    private let api: HaloAPI
    private var location: LocationService?
    private var locationCancellable: AnyCancellable?
    private var activationToken: String?
    private var lastAttemptAt = Date.distantPast
    private var uploadInFlight = false

    init(api: HaloAPI = .shared) {
        self.api = api
    }

    func bind(location: LocationService) {
        guard self.location !== location else { return }
        self.location = location
        locationCancellable?.cancel()
        locationCancellable = location.$location
            .compactMap { $0 }
            .sink { [weak self] fix in
                guard let self else { return }
                Task { @MainActor in
                    await self.handle(fix)
                }
            }
    }

    func reconcile(activationToken: String?, location: LocationService) async {
        bind(location: location)
        guard let activationToken, !activationToken.isEmpty else {
            deactivateLocationOnly()
            return
        }

        self.activationToken = activationToken
        do {
            let status = try await api.fetchClockStatus(activationToken: activationToken)
            let shouldTrack = status.entry?.attendanceOnly == true
                && status.entry?.running == true
                && status.gpsTracking?.active == true

            if shouldTrack, let gps = status.gpsTracking {
                activate(sessionID: gps.sessionID, activationToken: activationToken, location: location)
            } else {
                deactivateLocationOnly()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func activate(sessionID: String, activationToken: String, location: LocationService) {
        bind(location: location)
        self.activationToken = activationToken
        self.sessionID = sessionID
        isTracking = true
        lastError = nil
        location.startAttendanceTracking()
        location.refresh()

        if let fix = location.freshLocation(requiredAccuracy: 150) {
            Task { @MainActor in await handle(fix, force: true) }
        }
    }

    func deactivateLocationOnly() {
        isTracking = false
        sessionID = nil
        lastAttemptAt = .distantPast
        uploadInFlight = false
        location?.stopAttendanceTracking()
    }

    private func handle(_ fix: CLLocation, force: Bool = false) async {
        guard isTracking,
              let sessionID,
              let activationToken,
              fix.horizontalAccuracy >= 0,
              fix.horizontalAccuracy <= 150
        else { return }

        let now = Date()
        guard force || now.timeIntervalSince(lastAttemptAt) >= 20 else { return }
        guard !uploadInFlight else { return }

        lastAttemptAt = now
        uploadInFlight = true
        defer { uploadInFlight = false }

        do {
            try await api.updateGPSSession(
                id: sessionID,
                location: fix,
                activationToken: activationToken
            )
            lastUploadedAt = now
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            if case let HaloAPIError.http(status, _) = error, status == 404 || status == 409 {
                deactivateLocationOnly()
            }
        }
    }
}
