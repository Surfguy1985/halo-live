import AVFoundation
import CoreLocation
import SwiftData
import SwiftUI
import UIKit

struct WorkSessionCard: View {
    let job: FieldJob

    @EnvironmentObject private var session: HaloSessionStore
    @EnvironmentObject private var store: JobStore
    @EnvironmentObject private var network: NetworkMonitor
    @Environment(\.modelContext) private var modelContext
    @State private var status: HaloClockStatus?
    @State private var fetchedAt = Date()
    @State private var action: String?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("WORK SESSION")
                    .font(HaloType.body(10, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(.white.opacity(0.42))

                Spacer()

                if let entry = status?.entry, entry.jobID == job.id {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(entry.running ? HaloTheme.fieldLive : HaloTheme.warning)
                            .frame(width: 7, height: 7)
                        Text(entry.running ? "PAID TIME LIVE" : "PAUSED")
                            .font(HaloType.body(9, weight: .bold))
                            .tracking(1.0)
                            .foregroundStyle(entry.running ? HaloTheme.fieldLive : HaloTheme.warning)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                if isLoading && status == nil {
                    HStack(spacing: 10) {
                        ProgressView().tint(HaloTheme.lime)
                        Text("Checking Back Office hours…")
                            .font(HaloType.body(12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                } else if status?.configured == false {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(HaloTheme.warning)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Hours setup required")
                                .font(HaloType.body(14, weight: .bold))
                                .foregroundStyle(.white)
                            Text("This crew must be enrolled in Back Office Hours before paid work can start.")
                                .font(HaloType.body(11))
                                .foregroundStyle(.white.opacity(0.42))
                        }
                    }
                } else if let entry = status?.entry {
                    if entry.jobID == job.id {
                        currentSession(entry)
                    } else {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(HaloTheme.warning)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Another paid job is active")
                                    .font(HaloType.body(14, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("\(entry.property ?? "Property") · Unit \(entry.unitNumber ?? "—")")
                                    .font(HaloType.body(11))
                                    .foregroundStyle(.white.opacity(0.46))
                            }
                            Spacer()
                        }
                    }
                } else {
                    readyToStart
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(HaloType.body(10, weight: .semibold))
                        .foregroundStyle(HaloTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .haloDarkCard()
        }
        .task(id: session.activationToken) {
            await refresh()
        }
        .sheet(isPresented: Binding(
            get: { action != nil },
            set: { if !$0 { action = nil } }
        )) {
            if let action {
                WorkPunchView(job: job, kind: action) {
                    self.action = nil
                    Task {
                        await refresh()
                        await store.refresh(activationToken: session.activationToken)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func currentSession(_ entry: HaloClockEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(elapsedText(entry: entry, now: context.date))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text(entry.sessionType == "rework" ? "REWORK" : "AUTHORIZED WORK")
                        .font(HaloType.body(9, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(HaloTheme.lime)
                    Text(entry.running ? "Running" : "On break")
                        .font(HaloType.body(11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.44))
                }
            }

            HStack(spacing: 10) {
                if entry.running {
                    sessionButton(
                        title: "Break",
                        icon: "pause.fill",
                        primary: false,
                        action: "pause"
                    )
                } else {
                    sessionButton(
                        title: "Resume",
                        icon: "play.fill",
                        primary: true,
                        action: "resume"
                    )
                }

                sessionButton(
                    title: "End & Submit",
                    icon: "checkmark.seal.fill",
                    primary: entry.running,
                    action: "submit"
                )
            }

            Text("Every punch is verified with a live photo and fresh GPS. HALO Enforcer checks the action before paid time changes.")
                .font(HaloType.body(9, weight: .medium))
                .foregroundStyle(.white.opacity(0.32))
        }
    }

    private var readyToStart: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(HaloTheme.lime.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "clock.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(HaloTheme.lime)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Ready to start paid work")
                        .font(HaloType.body(14, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Live photo + GPS starts the Back Office work timer.")
                        .font(HaloType.body(11))
                        .foregroundStyle(.white.opacity(0.44))
                }
            }

            sessionButton(
                title: "Start Work",
                icon: "play.fill",
                primary: true,
                action: "start"
            )
        }
    }

    private func sessionButton(title: String, icon: String, primary: Bool, action: String) -> some View {
        Button {
            self.action = action
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            Label(title, systemImage: icon)
                .font(HaloType.body(11, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(primary ? HaloTheme.lime : Color.white.opacity(0.07))
                .foregroundStyle(primary ? HaloTheme.ink : .white)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func elapsedText(entry: HaloClockEntry, now: Date) -> String {
        var ms = entry.workedMs
        if entry.running {
            ms += Int(max(0, now.timeIntervalSince(fetchedAt)) * 1000)
        }
        let total = max(ms / 1000, 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func refresh() async {
        guard let token = session.activationToken, !token.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            status = try await HaloAPI.shared.fetchClockStatus(activationToken: token)
            fetchedAt = .now
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct WorkPunchView: View {
    let job: FieldJob
    let kind: String
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: HaloSessionStore
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var network: NetworkMonitor
    @Environment(\.modelContext) private var modelContext

    @StateObject private var camera: HaloCameraController
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var requestID = UUID()

    init(job: FieldJob, kind: String, onComplete: @escaping () -> Void) {
        self.job = job
        self.kind = kind
        self.onComplete = onComplete
        _camera = StateObject(wrappedValue: HaloCameraController(position: .front))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let image = camera.capturedImage {
                    review(image)
                } else {
                    cameraView
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.44))
                            .clipShape(Circle())
                    }
                    .foregroundStyle(.white)
                }
                ToolbarItem(placement: .principal) {
                    Text(actionTitle.uppercased())
                        .font(HaloType.body(10, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.76))
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .onAppear {
                location.requestPermission()
                location.refresh()
                camera.start()
            }
            .onDisappear {
                camera.stop()
            }
        }
    }

    private var cameraView: some View {
        ZStack {
            HaloCameraPreview(session: camera.session)
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.70), .clear, .black.opacity(0.86)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text(actionTitle)
                        .font(HaloType.display(26, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Unit \(job.unit) · \(job.propertyName)")
                        .font(HaloType.body(12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                }
                .padding(.top, 62)

                Spacer()

                VStack(spacing: 16) {
                    locationBadge

                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.72), lineWidth: 2)
                            .frame(width: 122, height: 122)
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 46, weight: .light))
                            .foregroundStyle(.white.opacity(0.66))
                    }

                    Text("CENTER YOUR FACE · LIVE PHOTO REQUIRED")
                        .font(HaloType.body(9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.62))

                    Button {
                        camera.capture()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        ZStack {
                            Circle().fill(.white).frame(width: 78, height: 78)
                            Circle().stroke(.black.opacity(0.25), lineWidth: 3).frame(width: 66, height: 66)
                        }
                    }
                    .disabled(!camera.isReady)
                    .opacity(camera.isReady ? 1 : 0.5)

                    Text("HALO VERIFIED WORK PUNCH")
                        .font(HaloType.body(9, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(.white.opacity(0.40))
                        .padding(.bottom, 24)
                }
            }
            .padding(.horizontal, 20)

            if let error = camera.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(HaloTheme.warning)
                    Text(error)
                        .font(HaloType.body(12, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Work Verification Settings", systemImage: "gearshape.fill")
                            .font(HaloType.body(11, weight: .bold))
                            .frame(minHeight: 44)
                    }
                    .foregroundStyle(HaloTheme.lime)
                }
                .padding(20)
                .background(.black.opacity(0.80))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(24)
            }
        }
    }

    private func review(_ image: UIImage) -> some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.62), .clear, .black.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                Spacer()

                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 8) {
                        metadataChip(icon: "camera.fill", text: "Live photo")
                        metadataChip(
                            icon: "location.fill",
                            text: location.freshLocation(requiredAccuracy: 100)
                                .map { "GPS ±\(Int(max($0.horizontalAccuracy, 0)))m" } ?? "GPS pending"
                        )
                    }

                    Text(actionTitle)
                        .font(HaloType.display(24, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Enforcer will verify assignment, GPS, job state, proof requirements, and Back Office authority before this punch changes paid time.")
                        .font(HaloType.body(11))
                        .foregroundStyle(.white.opacity(0.52))

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(HaloType.body(11, weight: .semibold))
                            .foregroundStyle(HaloTheme.warning)
                    }

                    Button {
                        submit(image)
                    } label: {
                        HStack {
                            Text(isSubmitting ? "Verifying…" : confirmTitle)
                            Spacer()
                            if isSubmitting {
                                ProgressView().tint(HaloTheme.ink)
                            } else {
                                Image(systemName: "checkmark")
                            }
                        }
                        .font(HaloType.body(14, weight: .bold))
                        .padding(.horizontal, 20)
                        .frame(height: 56)
                        .background(HaloTheme.lime)
                        .foregroundStyle(HaloTheme.ink)
                        .clipShape(Capsule())
                    }
                    .disabled(isSubmitting)

                    Button("Retake") {
                        errorMessage = nil
                        camera.retake()
                    }
                    .font(HaloType.body(12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
                    .frame(maxWidth: .infinity, minHeight: 42)
                }
                .padding(20)
                .background(.black.opacity(0.68))
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(20)
            }
        }
    }

    private var locationBadge: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(location.freshLocation(requiredAccuracy: 100) == nil ? HaloTheme.warning : HaloTheme.fieldLive)
                .frame(width: 7, height: 7)
            Text(location.freshLocation(requiredAccuracy: 100)
                 .map { "GPS READY · ±\(Int(max($0.horizontalAccuracy, 0)))m" } ?? "ACQUIRING PRECISE GPS")
                .font(HaloType.body(9, weight: .bold))
                .tracking(0.8)
        }
        .foregroundStyle(.white.opacity(0.82))
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(.black.opacity(0.46))
        .clipShape(Capsule())
    }

    private func metadataChip(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(HaloType.body(9, weight: .bold))
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(.white.opacity(0.10))
            .clipShape(Capsule())
    }

    private var actionTitle: String {
        switch kind {
        case "start": "Start Work"
        case "pause": "Start Break"
        case "resume": "Resume Work"
        case "submit": "End Work & Submit"
        default: "Verify Work"
        }
    }

    private var confirmTitle: String {
        switch kind {
        case "submit": "Verify & Submit"
        case "pause": "Verify & Start Break"
        case "resume": "Verify & Resume"
        default: "Verify & Start Work"
        }
    }

    private func submit(_ image: UIImage) {
        guard let token = session.activationToken else {
            errorMessage = "This iPhone is not activated."
            return
        }

        guard let fix = location.freshLocation(requiredAccuracy: 100) else {
            errorMessage = "HALO needs a fresh GPS fix within 100 m accuracy."
            location.refresh()
            return
        }

        guard let jpeg = verifiedJPEG(image) else {
            errorMessage = "HALO could not prepare the verification photo."
            return
        }

        isSubmitting = true
        errorMessage = nil

        Task {
            if !network.isConnected {
                await queueClockPunch(jpeg: jpeg, fix: fix, token: token)
                return
            }

            do {
                _ = try await HaloAPI.shared.punchClock(
                    kind: kind,
                    jobID: job.id,
                    imageData: jpeg,
                    location: fix,
                    requestID: requestID,
                    activationToken: token
                )
                await MainActor.run {
                    isSubmitting = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onComplete()
                    dismiss()
                }
            } catch {
                if case HaloAPIError.transport = error {
                    await queueClockPunch(jpeg: jpeg, fix: fix, token: token)
                    return
                }
                if case let HaloAPIError.http(status, _) = error, status >= 500 || status == 408 || status == 429 {
                    await queueClockPunch(jpeg: jpeg, fix: fix, token: token)
                    return
                }
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

    private func queueClockPunch(jpeg: Data, fix: CLLocation, token: String) async {
        do {
            let file = try await OfflineMediaStore.shared.save(jpeg, preferredExtension: "jpg")
            await MainActor.run {
                OfflineQueue.shared.enqueue(
                    id: requestID,
                    jobID: job.id,
                    kind: .clockPunch,
                    payload: [
                        "kind": kind,
                        "imagePath": file.path,
                        "lat": String(fix.coordinate.latitude),
                        "lng": String(fix.coordinate.longitude),
                        "accuracy": String(fix.horizontalAccuracy),
                        "capturedAt": ISO8601DateFormatter().string(from: fix.timestamp)
                    ],
                    activationToken: token,
                    context: modelContext
                )
                isSubmitting = false
                errorMessage = "Saved offline · HALO will sync this verified punch when service returns."
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onComplete()
                dismiss()
            }
        } catch {
            await MainActor.run {
                isSubmitting = false
                errorMessage = "HALO could not secure this offline punch. \(error.localizedDescription)"
                UINotificationFeedbackGenerator().notificationOccurred(.error)
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
