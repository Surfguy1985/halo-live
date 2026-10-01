import AVFoundation
import CoreLocation
import SwiftUI
import UIKit

struct ArrivalVerificationView: View {
    let job: FieldJob
    let previewMode: Bool
    let onVerified: (HaloAPI.CheckInResult?) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var session: HaloSessionStore

    @StateObject private var camera = HaloCameraController(position: .front)
    @State private var isVerifying = false
    @State private var message = "Take a live check-in photo. HALO will bind it to a fresh GPS fix and the property geofence."
    @State private var verified = false
    @State private var lastResult: HaloAPI.CheckInResult?
    @State private var checkInRequestID = UUID()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    identityHeader
                    capturePanel
                    verificationStatus

                    Text(message)
                        .font(HaloType.body(12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)

                    if let image = camera.capturedImage, !verified {
                        Button {
                            verify(image: image)
                        } label: {
                            HStack {
                                Text(isVerifying ? "Verifying Photo + GPS…" : "Verify Check-In")
                                Spacer()
                                if isVerifying {
                                    ProgressView().tint(HaloTheme.ink)
                                } else {
                                    Image(systemName: "checkmark.shield.fill")
                                }
                            }
                            .font(HaloType.body(15, weight: .bold))
                            .padding(.horizontal, 22)
                            .frame(height: 58)
                            .background(HaloTheme.lime)
                            .foregroundStyle(HaloTheme.ink)
                            .clipShape(Capsule())
                        }
                        .disabled(isVerifying)

                        Button("Retake Photo") {
                            checkInRequestID = UUID()
                            message = "Take a live check-in photo. HALO will bind it to a fresh GPS fix and the property geofence."
                            camera.retake()
                            location.refresh()
                        }
                        .font(HaloType.body(12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.64))
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }

                    if location.isDeniedOrRestricted && !verified {
                        settingsButton(
                            title: "Location Settings",
                            icon: "location.slash.fill"
                        )
                    }

                    if camera.authorization == .denied || camera.authorization == .restricted {
                        settingsButton(
                            title: "Camera Settings",
                            icon: "camera.fill"
                        )
                    }

#if DEBUG
                    if previewMode && !verified {
                        Button("Simulate verified arrival · DEBUG") {
                            verified = true
                            message = "DEBUG preview only — production requires a live photo and server GPS verification."
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                onVerified(nil)
                                dismiss()
                            }
                        }
                        .font(HaloType.body(11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.42))
                        .frame(minHeight: 44)
                    }
#endif
                }
                .padding(20)
                .padding(.bottom, 20)
            }
            .background(HaloTheme.fieldBackground.ignoresSafeArea())
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
                camera.start()
            }
            .onDisappear {
                camera.stop()
            }
        }
    }

    private var identityHeader: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(verified ? HaloTheme.lime.opacity(0.14) : HaloTheme.actionBlue.opacity(0.12))
                    .frame(width: 86, height: 86)
                Image(systemName: verified ? "checkmark.seal.fill" : "person.crop.circle.badge.checkmark")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(verified ? HaloTheme.lime : .white)
            }

            Text(verified ? "ARRIVAL VERIFIED" : "PHOTO CHECK-IN")
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
        .padding(.top, 6)
    }

    @ViewBuilder
    private var capturePanel: some View {
        if verified {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(HaloTheme.lime)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Identity + location captured")
                        .font(HaloType.body(14, weight: .bold))
                        .foregroundStyle(.white)
                    Text("The private check-in photo and GPS receipt are stored with this job.")
                        .font(HaloType.body(10))
                        .foregroundStyle(.white.opacity(0.44))
                }
                Spacer()
            }
            .padding(16)
            .haloDarkCard()
        } else if let image = camera.capturedImage {
            ZStack(alignment: .bottomLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 330)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack(spacing: 7) {
                    Image(systemName: "camera.fill")
                    Text("LIVE CHECK-IN PHOTO")
                }
                .font(HaloType.body(9, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(.white)
                .padding(12)
            }
            .frame(height: 330)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(HaloTheme.lime.opacity(0.7), lineWidth: 1)
            }
        } else {
            ZStack {
                HaloCameraPreview(session: camera.session)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                LinearGradient(
                    colors: [.black.opacity(0.42), .clear, .black.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .allowsHitTesting(false)

                VStack {
                    HStack {
                        locationBadge
                        Spacer()
                    }
                    .padding(14)

                    Spacer()

                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.74), lineWidth: 2)
                            .frame(width: 112, height: 112)
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Text("CENTER YOUR FACE")
                        .font(HaloType.body(9, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(.white.opacity(0.72))

                    Spacer()

                    Button {
                        camera.capture()
                        location.refresh()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        ZStack {
                            Circle().fill(.white).frame(width: 72, height: 72)
                            Circle().stroke(.black.opacity(0.25), lineWidth: 3).frame(width: 61, height: 61)
                        }
                    }
                    .disabled(!camera.isReady)
                    .opacity(camera.isReady ? 1 : 0.5)
                    .padding(.bottom, 18)
                    .accessibilityLabel("Capture live check-in photo")
                }

                if let error = camera.errorMessage {
                    VStack(spacing: 10) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(HaloTheme.warning)
                        Text(error)
                            .font(HaloType.body(12, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .background(.black.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(24)
                }
            }
            .frame(height: 360)
        }
    }

    private var verificationStatus: some View {
        VStack(spacing: 12) {
            statusRow(
                icon: camera.authorization == .authorized ? "camera.fill" : "camera.badge.ellipsis",
                title: "Live camera",
                value: camera.capturedImage == nil ? cameraStatusText : "Photo captured",
                good: camera.capturedImage != nil
            )
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
                good: location.freshLocation(requiredAccuracy: 100) != nil
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
    }

    private var locationBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(location.freshLocation(requiredAccuracy: 100) == nil ? HaloTheme.warning : HaloTheme.fieldLive)
                .frame(width: 7, height: 7)
            Text(location.freshLocation(requiredAccuracy: 100)
                .map { "GPS ±\(Int(max($0.horizontalAccuracy, 0)))m" } ?? "ACQUIRING GPS")
                .font(HaloType.body(9, weight: .bold))
                .tracking(0.7)
        }
        .foregroundStyle(.white.opacity(0.86))
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(.black.opacity(0.5))
        .clipShape(Capsule())
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

    private func settingsButton(title: String, icon: String) -> some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            Label(title, systemImage: icon)
                .font(HaloType.body(12, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.bordered)
        .tint(.white.opacity(0.7))
    }

    private var cameraStatusText: String {
        switch camera.authorization {
        case .authorized: camera.isReady ? "Ready" : "Starting camera"
        case .denied: "Denied in Settings"
        case .restricted: "Restricted"
        case .notDetermined: "Waiting for permission"
        @unknown default: "Unknown"
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
        return "Verified against the property radius on submit"
    }

    private func verify(image: UIImage) {
        if !location.hasLocationPermission {
            location.requestPermission()
            message = "Allow location access, then try Verify Check-In again."
            return
        }

        guard let token = session.activationToken, !token.isEmpty else {
            message = "This iPhone is not activated for a HALO crew."
            return
        }

        guard let jpeg = verifiedJPEG(image) else {
            message = "HALO could not prepare the live check-in photo."
            return
        }

        isVerifying = true
        message = "Getting a fresh GPS fix…"
        location.refresh()

        Task {
            var fix = location.freshLocation(requiredAccuracy: 100)
            if fix == nil {
                for _ in 0..<10 {
                    try? await Task.sleep(for: .milliseconds(650))
                    location.refresh()
                    if let candidate = location.freshLocation(requiredAccuracy: 100) {
                        fix = candidate
                        break
                    }
                }
            }

            guard let fix else {
                await MainActor.run {
                    isVerifying = false
                    message = "HALO couldn’t get a ≤100m GPS fix. Move near a window or outside, then try again."
                }
                return
            }

            await MainActor.run {
                message = "Matching the live photo and GPS fix to this property…"
            }

            do {
                let result = try await HaloAPI.shared.verifyCheckIn(
                    jobID: job.id,
                    latitude: fix.coordinate.latitude,
                    longitude: fix.coordinate.longitude,
                    accuracy: fix.horizontalAccuracy,
                    capturedAt: fix.timestamp,
                    imageData: jpeg,
                    requestID: checkInRequestID,
                    activationToken: token
                )
                await MainActor.run {
                    lastResult = result
                    verified = true
                    isVerifying = false
                    message = "Verified. Photo + GPS check-in is complete and Job Mode is unlocked."
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                try? await Task.sleep(for: .milliseconds(600))
                await MainActor.run {
                    onVerified(result)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isVerifying = false
                    message = error.localizedDescription
                    location.refresh()
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func verifiedJPEG(_ image: UIImage) -> Data? {
        for quality in [0.72, 0.60, 0.48, 0.36] {
            if let data = image.jpegData(compressionQuality: quality),
               data.count <= 4 * 1024 * 1024 {
                return data
            }
        }
        return nil
    }
}
