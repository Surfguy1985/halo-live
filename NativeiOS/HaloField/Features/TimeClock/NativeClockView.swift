import AVFoundation
import CoreLocation
import MapKit
import SwiftData
import SwiftUI
import UIKit

struct NativeClockView: View {
    @EnvironmentObject private var session: HaloSessionStore
    @EnvironmentObject private var store: JobStore
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var fieldSync: FieldSyncController
    @Environment(\.modelContext) private var modelContext

    @State private var status: HaloClockStatus?
    @State private var fetchedAt = Date()
    @State private var punchKind: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var gpsExpanded = false
    @State private var helpExpanded = false
    @State private var pendingAttendanceKind: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                clockCard
                jobsAndPhotos

                if let anchor = status?.anchor {
                    HaloExpandablePanel(
                        title: "Work-area GPS",
                        icon: "location.fill.viewfinder",
                        badge: "500 m",
                        expanded: $gpsExpanded
                    ) {
                        ClockAnchorMap(anchor: anchor)
                            .frame(height: 190)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        HStack(spacing: 9) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(HaloTheme.fieldLive)
                            Text("Today’s work area is anchored to the first verified photo clock-in. Resume punches must return inside this area.")
                                .font(HaloType.body(10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.46))
                        }
                    }
                }

                HaloExpandablePanel(
                    title: "Need help?",
                    icon: "questionmark.circle.fill",
                    expanded: $helpExpanded
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Missing punches require manager review. HALO does not silently deduct lunch or alter a saved time record.")
                            .font(HaloType.body(11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.50))

                        NavigationLink {
                            SyncIssuesView()
                        } label: {
                            HStack {
                                Label("Open saved field work", systemImage: "arrow.triangle.2.circlepath")
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .font(HaloType.body(11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minHeight: 44)
                        }
                    }
                }
            }
            .padding(.horizontal, HaloTheme.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 34)
        }
        .background(
            ZStack {
                HaloTheme.fieldBackground
                RadialGradient(
                    colors: [HaloTheme.actionBlue.opacity(0.14), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 360
                )
            }
            .ignoresSafeArea()
        )
        .toolbar(.hidden, for: .navigationBar)
        .task(id: session.activationToken) {
            refreshPending()
            await refresh()
        }
        .task(id: network.isConnected) {
            guard network.isConnected, let token = session.activationToken else { return }
            await fieldSync.flush(context: modelContext, activationToken: token)
            refreshPending()
            await refresh()
        }
        .refreshable {
            if network.isConnected, let token = session.activationToken {
                await fieldSync.flush(context: modelContext, activationToken: token)
            }
            refreshPending()
            await refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .haloPendingActionCreated)) { _ in
            refreshPending()
        }
        .onReceive(NotificationCenter.default.publisher(for: .haloDataInvalidated)) { note in
            guard network.isConnected else { return }
            if let payload = note.object as? [String: Any],
               let scopes = payload["scopes"] as? [String],
               !scopes.contains("jobs") && !scopes.contains("live") {
                return
            }
            Task { await refresh() }
        }
        .sheet(isPresented: Binding(
            get: { punchKind != nil },
            set: { if !$0 { punchKind = nil } }
        )) {
            if let punchKind {
                AttendancePunchView(kind: punchKind) {
                    self.punchKind = nil
                    Task {
                        await refresh()
                        await store.refresh(activationToken: session.activationToken)
                        fieldSync.refreshPendingCount(context: modelContext, activationToken: session.activationToken)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("TIME CLOCK")
                    .font(HaloType.body(10, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(HaloTheme.actionBlue)
                Text(status?.profileName.isEmpty == false ? status!.profileName : (session.activationInfo?.crewName ?? "Your time"))
                    .font(HaloType.display(28, weight: .semibold))
                    .tracking(-0.8)
                    .foregroundStyle(.white)
            }
            Spacer()
            Button {
                Task { await refresh() }
            } label: {
                Image(systemName: isLoading ? "hourglass" : "arrow.clockwise")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(HaloPressableStyle())
            .disabled(isLoading)
        }
    }

    private var clockCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                AsyncImage(url: status?.latestPhotoURL.flatMap(URL.init(string:))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(HaloTheme.actionBlue.opacity(0.12))
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(HaloTheme.actionBlue)
                        }
                    }
                }
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("EMPLOYEE")
                        .font(HaloType.body(8, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.30))
                    Text(status?.profileName.isEmpty == false ? status!.profileName : (session.activationInfo?.crewName ?? "HALO Crew"))
                        .font(HaloType.body(15, weight: .bold))
                        .foregroundStyle(.white)
                }

                Spacer()
                statusPill
            }
            .padding(16)

            Divider().overlay(HaloTheme.hairline)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(timeText(at: context.date))
                                .font(.system(size: 40, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                        }
                        Text(status?.entry == nil ? "TODAY" : "THIS SHIFT")
                            .font(HaloType.body(9, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(.white.opacity(0.30))
                    }
                    Spacer()
                    Image(systemName: "clock.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.20))
                }

                if status?.configured == false {
                    Label("Back Office Hours setup is required before this crew can clock in.", systemImage: "clock.badge.exclamationmark")
                        .font(HaloType.body(11, weight: .semibold))
                        .foregroundStyle(HaloTheme.warning)
                } else if let entry = status?.entry, !entry.attendanceOnly {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Authorized unit timer is active", systemImage: "briefcase.fill")
                            .font(HaloType.body(12, weight: .bold))
                            .foregroundStyle(HaloTheme.warning)
                        Text([entry.property, entry.unitNumber.map { "Unit \($0)" }].compactMap { $0 }.joined(separator: " · "))
                            .font(HaloType.body(11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.46))
                        Button {
                            NotificationCenter.default.post(name: .haloOpenJobs, object: nil)
                        } label: {
                            Label("Open active job", systemImage: "arrow.up.right")
                                .font(HaloType.body(12, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundStyle(HaloTheme.ink)
                                .background(HaloTheme.lime, in: Capsule())
                        }
                        .buttonStyle(HaloPressableStyle())
                    }
                } else {
                    attendanceActions
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(HaloType.body(10, weight: .semibold))
                        .foregroundStyle(HaloTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Every time punch uses a live front-camera photo and a fresh precise GPS receipt. Your first clock-in sets today’s 500 m work area.")
                    .font(HaloType.body(9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.32))
            }
            .padding(18)
        }
        .haloDarkCard()
    }

    @ViewBuilder
    private var attendanceActions: some View {
        if let pendingAttendanceKind {
            VStack(alignment: .leading, spacing: 11) {
                Label("Saved verified punch", systemImage: "icloud.and.arrow.up.fill")
                    .font(HaloType.body(12, weight: .bold))
                    .foregroundStyle(HaloTheme.lime)
                Text("\(pendingLabel(pendingAttendanceKind)) is securely saved on this iPhone and must sync before another time punch.")
                    .font(HaloType.body(11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.48))
                if network.isConnected {
                    Button {
                        Task {
                            guard let token = session.activationToken else { return }
                            await fieldSync.flush(context: modelContext, activationToken: token)
                            refreshPending()
                            await refresh()
                        }
                    } label: {
                        Label("Sync saved punch", systemImage: "arrow.triangle.2.circlepath")
                            .font(HaloType.body(12, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(HaloTheme.ink)
                            .background(HaloTheme.lime, in: Capsule())
                    }
                    .buttonStyle(HaloPressableStyle())
                }
            }
            .padding(14)
            .background(HaloTheme.lime.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HaloTheme.lime.opacity(0.14)) }
        } else if let entry = status?.entry {
            if entry.running {
                actionButton(title: "Photo clock-out", icon: "camera.fill", primary: true) {
                    punchKind = "checkout"
                }
                actionButton(
                    title: workedMilliseconds(at: .now) >= 4 * 60 * 60 * 1000 ? "Lunch recommended" : "Start lunch break",
                    icon: "cup.and.saucer.fill",
                    primary: false
                ) {
                    punchKind = "pause"
                }
            } else {
                actionButton(title: "Photo clock-in again", icon: "camera.fill", primary: true) {
                    punchKind = "resume"
                }
                actionButton(title: "Finish day · photo clock-out", icon: "rectangle.portrait.and.arrow.right", primary: false) {
                    punchKind = "checkout"
                }
            }
        } else {
            actionButton(title: "Photo clock-in", icon: "camera.fill", primary: true) {
                punchKind = "start"
            }
        }
    }

    private func actionButton(title: String, icon: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            Label(title, systemImage: icon)
                .font(HaloType.body(13, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 54)
                .foregroundStyle(primary ? HaloTheme.ink : .white.opacity(0.76))
                .background(primary ? HaloTheme.lime : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay {
                    if !primary {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(Color.white.opacity(0.08))
                    }
                }
        }
        .buttonStyle(HaloPressableStyle())
        .disabled(status?.configured == false)
    }

    private var jobsAndPhotos: some View {
        Button {
            NotificationCenter.default.post(name: .haloOpenJobs, object: nil)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(HaloTheme.lime.opacity(0.11))
                        .frame(width: 48, height: 48)
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(HaloTheme.lime)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Jobs & Photos")
                        .font(HaloType.body(14, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Choose a unit and follow the next field step.")
                        .font(HaloType.body(10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.40))
                }

                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.30))
            }
            .padding(15)
            .haloDarkCard()
        }
        .buttonStyle(HaloPressableStyle())
    }

    private var statusPill: some View {
        let entry = status?.entry
        let text: String
        let tint: Color
        if status?.configured == false {
            text = "SETUP NEEDED"
            tint = HaloTheme.warning
        } else if entry?.running == true {
            text = "CLOCKED IN"
            tint = HaloTheme.fieldLive
        } else if entry?.pauseReason == "lunch" {
            text = "ON LUNCH"
            tint = HaloTheme.warning
        } else if entry != nil {
            text = "PAUSED"
            tint = HaloTheme.warning
        } else {
            text = "OFF CLOCK"
            tint = .white.opacity(0.46)
        }
        return HaloStatusPill(text: text, tint: tint)
    }

    private func workedMilliseconds(at now: Date) -> Int {
        let base = status?.todayWorkedMs ?? 0
        guard status?.entry?.running == true else { return base }
        return base + Int(max(0, now.timeIntervalSince(fetchedAt)) * 1000)
    }

    private func timeText(at now: Date) -> String {
        let total = max(workedMilliseconds(at: now) / 1000, 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func refreshPending() {
        let pending = OfflineQueue.shared.scopedActions(in: modelContext, activationToken: session.activationToken)
            .filter { $0.kind == PendingActionKind.clockPunch.rawValue && $0.jobID == "__attendance__" }
            .sorted { $0.createdAt > $1.createdAt }
            .first
        guard let pending,
              let object = try? JSONSerialization.jsonObject(with: pending.payload) as? [String: String]
        else {
            pendingAttendanceKind = nil
            return
        }
        pendingAttendanceKind = object["kind"]
    }

    private func pendingLabel(_ kind: String) -> String {
        switch kind {
        case "start": "Photo clock-in"
        case "pause": "Lunch punch"
        case "resume": "Photo clock-in again"
        case "checkout": "Photo clock-out"
        default: "Time punch"
        }
    }

    @MainActor
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

private struct ClockAnchorMap: View {
    let anchor: HaloClockAnchor
    @State private var position: MapCameraPosition

    init(anchor: HaloClockAnchor) {
        self.anchor = anchor
        let center = CLLocationCoordinate2D(latitude: anchor.latitude, longitude: anchor.longitude)
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.014, longitudeDelta: 0.014)
        )))
    }

    var body: some View {
        let center = CLLocationCoordinate2D(latitude: anchor.latitude, longitude: anchor.longitude)
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            MapCircle(center: center, radius: anchor.radius)
                .foregroundStyle(HaloTheme.actionBlue.opacity(0.12))
                .stroke(HaloTheme.actionBlue.opacity(0.60), lineWidth: 1.5)
            Annotation("Clock-in", coordinate: center) {
                ZStack {
                    HaloPulseRing(tint: HaloTheme.lime).frame(width: 48, height: 48)
                    Circle().fill(HaloTheme.lime).frame(width: 30, height: 30)
                    Image(systemName: "person.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(HaloTheme.ink)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }
}

private struct AttendancePunchView: View {
    let kind: String
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: HaloSessionStore
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var network: NetworkMonitor
    @Environment(\.modelContext) private var modelContext

    @StateObject private var camera = HaloCameraController(position: .front)
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var requestID = UUID()

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
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 38, height: 38)
                            .background(.black.opacity(0.44), in: Circle())
                    }
                    .foregroundStyle(.white)
                }
                ToolbarItem(placement: .principal) { HaloLogo(height: 22) }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .onAppear {
                location.requestPermission()
                location.refresh()
                camera.start()
            }
            .onDisappear { camera.stop() }
        }
    }

    private var cameraView: some View {
        ZStack {
            HaloCameraPreview(session: camera.session).ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.72), .clear, .black.opacity(0.88)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack {
                VStack(spacing: 6) {
                    Text(actionTitle)
                        .font(HaloType.display(27, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Verified time punch")
                        .font(HaloType.body(10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.46))
                }
                .padding(.top, 60)

                Spacer()

                VStack(spacing: 16) {
                    locationBadge
                    ZStack {
                        Circle().stroke(.white.opacity(0.72), lineWidth: 2).frame(width: 124, height: 124)
                        Image(systemName: "person.crop.circle").font(.system(size: 46, weight: .light)).foregroundStyle(.white.opacity(0.68))
                    }
                    Text("CENTER YOUR FACE · LIVE PHOTO REQUIRED")
                        .font(HaloType.body(9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.62))

                    Button {
                        location.refresh()
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

                    Text("PHOTO + GPS · HALO TIME CLOCK")
                        .font(HaloType.body(9, weight: .bold))
                        .tracking(1.3)
                        .foregroundStyle(.white.opacity(0.38))
                        .padding(.bottom, 24)
                }
            }
            .padding(.horizontal, 20)

            if let cameraError = camera.errorMessage {
                Text(cameraError)
                    .font(HaloType.body(12, weight: .semibold))
                    .foregroundStyle(HaloTheme.warning)
                    .multilineTextAlignment(.center)
                    .padding(18)
                    .background(.black.opacity(0.80), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(24)
            }
        }
    }

    private func review(_ image: UIImage) -> some View {
        ZStack {
            Image(uiImage: image).resizable().scaledToFill().ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.60), .clear, .black.opacity(0.94)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()

            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 8) {
                        chip(icon: "camera.fill", text: "Live photo")
                        chip(icon: "location.fill", text: location.freshLocation(requiredAccuracy: 100).map { "GPS ±\(Int(max($0.horizontalAccuracy, 0)))m" } ?? "GPS pending")
                    }
                    Text(actionTitle).font(HaloType.display(25, weight: .semibold)).foregroundStyle(.white)
                    Text(explanation).font(HaloType.body(11, weight: .medium)).foregroundStyle(.white.opacity(0.54))

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(HaloType.body(10, weight: .semibold))
                            .foregroundStyle(HaloTheme.warning)
                    }

                    Button { submit(image) } label: {
                        HStack {
                            Text(isSubmitting ? "Saving verified punch…" : confirmTitle)
                            Spacer()
                            if isSubmitting { ProgressView().tint(HaloTheme.ink) }
                            else { Image(systemName: "checkmark.shield.fill") }
                        }
                    }
                    .buttonStyle(HaloPrimaryButtonStyle())
                    .disabled(isSubmitting)

                    Button("Retake photo") {
                        errorMessage = nil
                        requestID = UUID()
                        camera.retake()
                        location.refresh()
                    }
                    .font(HaloType.body(12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.68))
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(20)
                .background(.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(20)
            }
        }
    }

    private var locationBadge: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(location.freshLocation(requiredAccuracy: 100) == nil ? HaloTheme.warning : HaloTheme.fieldLive)
                .frame(width: 7, height: 7)
            Text(location.freshLocation(requiredAccuracy: 100).map { "GPS READY · ±\(Int(max($0.horizontalAccuracy, 0)))m" } ?? "ACQUIRING PRECISE GPS")
                .font(HaloType.body(9, weight: .bold))
                .tracking(0.7)
        }
        .foregroundStyle(.white.opacity(0.84))
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(.black.opacity(0.48), in: Capsule())
    }

    private func chip(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(HaloType.body(9, weight: .bold))
            .foregroundStyle(.white.opacity(0.84))
            .padding(.horizontal, 10)
            .frame(height: 31)
            .background(.white.opacity(0.10), in: Capsule())
    }

    private var actionTitle: String {
        switch kind {
        case "start": "Photo clock-in"
        case "pause": "Start lunch break"
        case "resume": "Photo clock-in again"
        case "checkout": "Photo clock-out"
        default: "Verified time punch"
        }
    }

    private var confirmTitle: String {
        switch kind {
        case "pause": "Verify & start lunch"
        case "resume": "Verify & resume"
        case "checkout": "Verify & clock out"
        default: "Verify & clock in"
        }
    }

    private var explanation: String {
        switch kind {
        case "pause": "This pauses paid time for lunch. Resume requires another live photo and a fresh GPS fix."
        case "resume": "HALO verifies that you returned inside today’s work area before paid time resumes."
        case "checkout": "Your live photo and GPS receipt end today’s shift. Job photos can remain separate from payroll time."
        default: "This live photo and GPS receipt start today’s shift and establish the 500 m work area."
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
            errorMessage = "HALO could not prepare the live verification photo."
            return
        }

        isSubmitting = true
        errorMessage = nil

        Task {
            if !network.isConnected {
                await queueOffline(jpeg: jpeg, fix: fix, token: token)
                return
            }
            do {
                _ = try await HaloAPI.shared.punchClock(
                    kind: kind,
                    jobID: "__attendance__",
                    attendanceOnly: true,
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
                    await queueOffline(jpeg: jpeg, fix: fix, token: token)
                    return
                }
                if case let HaloAPIError.http(status, _) = error, status >= 500 || status == 408 || status == 429 {
                    await queueOffline(jpeg: jpeg, fix: fix, token: token)
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

    private func queueOffline(jpeg: Data, fix: CLLocation, token: String) async {
        do {
            let file = try await OfflineMediaStore.shared.save(jpeg, preferredExtension: "jpg")
            await MainActor.run {
                OfflineQueue.shared.enqueue(
                    id: requestID,
                    jobID: "__attendance__",
                    kind: .clockPunch,
                    payload: [
                        "kind": kind,
                        "attendanceOnly": "true",
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
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onComplete()
                dismiss()
            }
        } catch {
            await MainActor.run {
                isSubmitting = false
                errorMessage = "HALO could not secure this offline punch. \(error.localizedDescription)"
            }
        }
    }

    private func verifiedJPEG(_ image: UIImage) -> Data? {
        for quality in [0.72, 0.60, 0.48, 0.36] {
            if let data = image.jpegData(compressionQuality: quality), data.count <= 4 * 1024 * 1024 {
                return data
            }
        }
        return nil
    }
}
