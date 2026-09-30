import CoreLocation
import SwiftUI

struct ArrivalVerificationView: View {
    let job: FieldJob
#if DEBUG
    let previewMode: Bool
#endif
    let onVerified: (HaloAPI.CheckInResult?) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var session: HaloSessionStore

    @State private var isVerifying = false
    @State private var message = "HALO needs a fresh GPS fix before work can begin."
    @State private var verified = false
    @State private var lastResult: HaloAPI.CheckInResult?

    var body: some View {
        NavigationStack {
            ZStack {
                HaloTheme.fieldBackground.ignoresSafeArea()

                VStack(spacing: 22) {
                    Spacer(minLength: 10)

                    ZStack {
                        Circle()
                            .fill(verified ? HaloTheme.lime.opacity(0.14) : HaloTheme.actionBlue.opacity(0.12))
                            .frame(width: 118, height: 118)
                        Circle()
                            .stroke(verified ? HaloTheme.lime : HaloTheme.actionBlue.opacity(0.55), lineWidth: 1.5)
                            .frame(width: 92, height: 92)
                        Image(systemName: verified ? "checkmark.seal.fill" : "location.circle.fill")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(verified ? HaloTheme.lime : .white)
                    }

                    VStack(spacing: 7) {
                        Text(verified ? "ARRIVAL VERIFIED" : "VERIFY ARRIVAL")
                            .font(HaloType.body(10, weight: .bold))
                            .tracking(1.8)
                            .foregroundStyle(verified ? HaloTheme.lime : .white.opacity(0.48))
                        Text("Unit \(job.unit)")
                            .font(HaloType.display(34, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(job.propertyName)
                            .font(HaloType.card(16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    VStack(spacing: 12) {
                        statusRow(
                            icon: location.hasLocationPermission ? "location.fill" : "location.slash.fill",
                            title: "Location permission",
                            value: permissionText,
                            good: location.hasLocationPermission
                        )
                        statusRow(
                            icon: "scope",
                            title: "GPS accuracy",
                            value: accuracyText,
                            good: location.freshLocation() != nil
                        )
                        statusRow(
                            icon: "mappin.and.ellipse",
                            title: "Property geofence",
                            value: geofenceText,
                            good: verified
                        )
                    }
                    .padding(18)
                    .haloDarkCard()

                    Text(message)
                        .font(HaloType.body(12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.54))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                    Spacer()

                    Button {
                        verify()
                    } label: {
                        HStack {
                            Text(isVerifying ? "Verifying…" : (location.hasLocationPermission ? "Verify My Location" : "Enable Location"))
                            Spacer()
                            if isVerifying {
                                ProgressView().tint(HaloTheme.ink)
                            } else {
                                Image(systemName: "location.fill")
                            }
                        }
                        .font(HaloType.body(15, weight: .bold))
                        .padding(.horizontal, 22)
                        .frame(height: 58)
                        .background(verified ? HaloTheme.success : HaloTheme.lime)
                        .foregroundStyle(HaloTheme.ink)
                        .clipShape(Capsule())
                    }
                    .disabled(isVerifying || verified)

#if DEBUG
                    if previewMode && !verified {
                        Button("Simulate verified arrival · DEBUG") {
                            verified = true
                            message = "DEBUG preview only — production still requires server GPS verification."
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                onVerified(nil)
                                dismiss()
                            }
                        }
                        .font(HaloType.body(11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(minHeight: 44)
                    }
#endif
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.72))
                }
                ToolbarItem(placement: .principal) {
                    HaloLogo(height: 22)
                }
            }
            .toolbarBackground(HaloTheme.fieldBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                if location.authorization == .notDetermined {
                    location.requestPermission()
                }
                location.refresh()
            }
        }
    }

    private func statusRow(icon: String, title: String, value: String, good: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 30)
                .foregroundStyle(good ? HaloTheme.lime : HaloTheme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(HaloType.body(12, weight: .bold))
                    .foregroundStyle(.white)
                Text(value)
                    .font(HaloType.body(10))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            Image(systemName: good ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(good ? HaloTheme.lime : .white.opacity(0.25))
        }
    }

    private var permissionText: String {
        switch location.authorization {
        case .authorizedAlways, .authorizedWhenInUse: "Allowed"
        case .denied: "Denied in Settings"
        case .restricted: "Restricted"
        case .notDetermined: "Waiting for permission"
        @unknown default: "Unknown"
        }
    }

    private var accuracyText: String {
        guard let fix = location.location else { return "Acquiring a fresh fix" }
        let age = abs(fix.timestamp.timeIntervalSinceNow)
        if age > 120 { return "Location is stale — refreshing" }
        if fix.horizontalAccuracy > 100 { return "±\(Int(fix.horizontalAccuracy))m · need ≤100m" }
        return "±\(Int(max(fix.horizontalAccuracy, 0)))m · ready"
    }

    private var geofenceText: String {
        if let result = lastResult {
            return "\(result.distanceMeters)m from property · allowed \(result.allowedRadiusMeters)m"
        }
        return "300m verified property radius"
    }

    private func verify() {
        if !location.hasLocationPermission {
            location.requestPermission()
            message = "Allow location access, then verify again."
            return
        }

        guard let fix = location.freshLocation() else {
            location.refresh()
            message = "Getting a fresh, accurate GPS fix. Try again in a moment."
            return
        }

        guard let token = session.activationToken, !token.isEmpty else {
            message = "This iPhone is not activated for a HALO crew."
            return
        }

        isVerifying = true
        message = "Confirming your arrival with HALO…"

        Task {
            do {
                let result = try await HaloAPI.shared.verifyCheckIn(
                    jobID: job.id,
                    latitude: fix.coordinate.latitude,
                    longitude: fix.coordinate.longitude,
                    accuracy: fix.horizontalAccuracy,
                    capturedAt: fix.timestamp,
                    activationToken: token
                )
                await MainActor.run {
                    lastResult = result
                    verified = true
                    isVerifying = false
                    message = "Verified. You’re checked in and Job Mode is unlocked."
                }
                try? await Task.sleep(for: .milliseconds(500))
                await MainActor.run {
                    onVerified(result)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isVerifying = false
                    message = error.localizedDescription
                    location.refresh()
                }
            }
        }
    }
}
