import MapKit
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var session: HaloSessionStore
    @EnvironmentObject private var store: JobStore
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var fieldSync: FieldSyncController
    @EnvironmentObject private var realtime: HaloRealtimeService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0

    var body: some View {
        Group {
#if DEBUG
            if session.isActivated || store.isPreviewMode {
                tabShell
            } else {
                ActivationView()
            }
#else
            if session.isActivated {
                tabShell
            } else {
                ActivationView()
            }
#endif
        }
        .task(id: session.activationToken) {
#if DEBUG
            if store.isPreviewMode {
                fieldSync.refreshPendingCount(context: modelContext, activationToken: session.activationToken)
                return
            }
#endif
            guard session.isActivated else {
                store.clear()
                fieldSync.refreshPendingCount(context: modelContext, activationToken: session.activationToken)
                return
            }
            await session.refreshValidation()
            await store.loadIfNeeded(activationToken: session.activationToken)
            if network.isConnected {
                await fieldSync.flush(context: modelContext, activationToken: session.activationToken)
            }

            // Keep Today + Jobs synchronized while the app is open. APNs remains
            // the immediate invalidation path; this 15-second refresh is the
            // resilience path for simulator builds and missed push delivery.
            while !Task.isCancelled {
                let fallbackSeconds = realtime.state == .connected ? 60.0 : 15.0
                try? await Task.sleep(for: .seconds(fallbackSeconds))
                guard session.isActivated, network.isConnected, scenePhase == .active else { continue }
                await store.refresh(activationToken: session.activationToken)
            }
        }
        .task(id: network.isConnected) {
            guard network.isConnected else {
                fieldSync.refreshPendingCount(context: modelContext, activationToken: session.activationToken)
                return
            }
            await fieldSync.flush(context: modelContext, activationToken: session.activationToken)
            if session.isActivated {
                await store.refresh(activationToken: session.activationToken)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            fieldSync.refreshPendingCount(context: modelContext, activationToken: session.activationToken)
            if network.isConnected {
                await store.refresh(activationToken: session.activationToken)
                await fieldSync.flush(context: modelContext, activationToken: session.activationToken)
            }
        }
        .onChange(of: session.managerLiveAccess) { _, allowed in
            if !allowed && selectedTab == 3 { selectedTab = 0 }
        }
        .onChange(of: session.activationToken) { _, _ in selectedTab = 0 }
        .onReceive(NotificationCenter.default.publisher(for: .haloOpenJob)) { note in
            guard let jobID = note.object as? String else { return }
            store.selectedJobID = jobID
            selectedTab = 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .haloOpenComms)) { _ in
            selectedTab = 2
        }
        .onReceive(NotificationCenter.default.publisher(for: .haloPendingActionCreated)) { _ in
            fieldSync.refreshPendingCount(context: modelContext, activationToken: session.activationToken)
            guard network.isConnected else { return }
            Task {
                await fieldSync.flush(context: modelContext, activationToken: session.activationToken)
                await store.refresh(activationToken: session.activationToken)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .haloDataInvalidated)) { note in
            guard session.isActivated, network.isConnected else { return }
            if let payload = note.object as? [String: Any],
               let scopes = payload["scopes"] as? [String],
               !scopes.contains("jobs") {
                return
            }
            Task {
                await store.refresh(activationToken: session.activationToken)
            }
        }
    }

    private var tabShell: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { TodayView() }
                .tag(0)

            NavigationStack { JobsView() }
                .tag(1)

            NavigationStack { HaloCommsView() }
                .tag(2)

            if session.managerLiveAccess {
                NavigationStack { ManagerLiveView() }
                    .tag(3)
            }

            NavigationStack { ProfileView() }
                .tag(4)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HaloNativeTabBar(
                selection: $selectedTab,
                managerLiveAccess: session.managerLiveAccess
            )
            .padding(.horizontal, 12)
            .padding(.top, 7)
            .padding(.bottom, 7)
        }
        .background(HaloTheme.fieldBackground)
    }
}

private struct HaloNativeTabBar: View {
    @Binding var selection: Int
    let managerLiveAccess: Bool
    @Namespace private var selectionAnimation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var items: [(id: Int, title: String, icon: String)] {
        var rows: [(Int, String, String)] = [
            (0, "Today", "bolt.fill"),
            (1, "Jobs", "square.stack.3d.up.fill"),
            (2, "Messages", "bubble.left.and.bubble.right.fill")
        ]
        if managerLiveAccess {
            rows.append((3, "Live", "map.fill"))
        }
        rows.append((4, "Me", "person.crop.circle.fill"))
        return rows
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.id) { item in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.78)) {
                        selection = item.id
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    if item.id == 2 {
                        haloButton(item)
                    } else {
                        standardButton(item)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selection == item.id ? .isSelected : [])
            }
        }
        .padding(5)
        .frame(minHeight: 66)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(HaloTheme.fieldChrome.opacity(0.78), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.22), radius: 20, y: 10)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func standardButton(_ item: (id: Int, title: String, icon: String)) -> some View {
        let selected = selection == item.id
        VStack(spacing: 3) {
            ZStack {
                if selected {
                    Capsule()
                        .fill(Color.white.opacity(0.09))
                        .matchedGeometryEffect(id: "halo-tab-selection", in: selectionAnimation)
                        .frame(width: 42, height: 26)
                }
                Image(systemName: item.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected ? HaloTheme.lime : .white.opacity(0.48))
            }
            .frame(height: 28)

            Text(item.title)
                .font(HaloType.body(11, weight: .semibold))
                .foregroundStyle(selected ? .white : .white.opacity(0.42))
        }
        .frame(maxWidth: .infinity, minHeight: HaloTheme.minimumTapTarget)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func haloButton(_ item: (id: Int, title: String, icon: String)) -> some View {
        let selected = selection == item.id
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(selected ? HaloTheme.lime : Color.white)
                    .frame(width: 40, height: 40)
                    .shadow(color: (selected ? HaloTheme.lime : .white).opacity(0.20), radius: 12, y: 4)
                Image(systemName: item.icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(HaloTheme.ink)
            }
            .scaleEffect(selected ? 1.05 : 1)

            Text("Messages")
                .font(HaloType.body(10, weight: .bold))
                .tracking(0.35)
                .foregroundStyle(selected ? HaloTheme.lime : .white.opacity(0.48))
        }
        .frame(maxWidth: .infinity, minHeight: HaloTheme.minimumTapTarget)
        .offset(y: -2)
        .contentShape(Rectangle())
    }
}


private struct ProfileView: View {
    @EnvironmentObject private var session: HaloSessionStore
    @EnvironmentObject private var store: JobStore
    @EnvironmentObject private var fieldSync: FieldSyncController
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var notifications: HaloNotificationService
    @State private var profilePhotoURL: String?
    @State private var profileName = "Crew profile"
    @State private var selectedProfilePhoto: PhotosPickerItem?
    @State private var profilePhotoBusy = false
    @State private var profilePhotoError: String?

    private var notificationStatusText: String {
        switch notifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral: "On"
        case .denied: "Off"
        case .notDetermined: "Set up"
        @unknown default: "Unknown"
        }
    }

    private var notificationStatusColor: Color {
        switch notifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral: HaloTheme.fieldLive
        case .denied: HaloTheme.warning
        case .notDetermined: HaloTheme.actionBlue
        @unknown default: .white.opacity(0.45)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HaloTheme.sectionSpacing) {
                profileHero

                VStack(alignment: .leading, spacing: 12) {
                    HaloSectionLabel(title: "Field")
                    NavigationLink { SyncIssuesView() } label: {
                        settingRow(
                            icon: network.isConnected ? "arrow.triangle.2.circlepath" : "wifi.slash",
                            title: network.isConnected ? "Field sync" : "Offline mode",
                            subtitle: fieldSync.attentionCount > 0 ? "\(fieldSync.attentionCount) need attention" : (fieldSync.pendingCount == 0 ? "Everything is up to date" : "\(fieldSync.pendingCount) saved changes"),
                            tint: fieldSync.pendingCount == 0 && fieldSync.attentionCount == 0 ? HaloTheme.fieldLive : HaloTheme.warning,
                            trailing: "chevron.right"
                        )
                    }
                    .buttonStyle(HaloPressableStyle())

                    settingRow(icon: "location.fill", title: "Location verification", subtitle: "Used only for assigned field work and active sharing.", tint: HaloTheme.actionBlue)

                    Button {
                        if notifications.authorizationStatus == .denied {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        } else {
                            Task {
                                if notifications.authorizationStatus == .notDetermined {
                                    _ = await notifications.requestAuthorization()
                                } else {
                                    await notifications.refreshAuthorization()
                                }
                            }
                        }
                    } label: {
                        settingRow(icon: "bell.fill", title: "Notifications", subtitle: "Assignments, messages, rework and job updates.", tint: notificationStatusColor, badge: notificationStatusText)
                    }
                    .buttonStyle(HaloPressableStyle())
                }

                VStack(alignment: .leading, spacing: 12) {
                    HaloSectionLabel(title: "This iPhone")
                    Button(role: .destructive) {
                        let token = session.activationToken
                        Task { await notifications.unregisterRemoteDevice(activationToken: token) }
                        store.clear(removeCache: true)
                        session.deactivate()
                    } label: {
                        settingRow(icon: "rectangle.portrait.and.arrow.right", title: "Deactivate this iPhone", subtitle: "Removes this device's HALO activation.", tint: HaloTheme.danger)
                    }
                    .buttonStyle(HaloPressableStyle())
                    .disabled(fieldSync.pendingCount > 0 || fieldSync.attentionCount > 0)

                    if fieldSync.pendingCount > 0 || fieldSync.attentionCount > 0 {
                        Label("Resolve saved field work before deactivating this iPhone.", systemImage: "exclamationmark.triangle.fill")
                            .font(HaloType.body(10, weight: .semibold))
                            .foregroundStyle(HaloTheme.warning)
                            .padding(.horizontal, 4)
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
                RadialGradient(colors: [HaloTheme.actionBlue.opacity(0.12), .clear], center: .topTrailing, startRadius: 0, endRadius: 330)
            }.ignoresSafeArea()
        )
        .navigationTitle("Me")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: session.activationToken) { await loadProfilePhoto() }
        .onChange(of: selectedProfilePhoto) { _, item in
            guard let item else { return }
            Task { await uploadProfilePhoto(item) }
        }
    }

    private var profileHero: some View {
        HStack(spacing: 16) {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: profilePhotoURL.flatMap(URL.init(string:))) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default:
                        ZStack {
                            Circle().fill(Color.white.opacity(0.07))
                            Image(systemName: "person.crop.circle.fill").font(.system(size: 46)).foregroundStyle(.white.opacity(0.42))
                        }
                    }
                }
                .frame(width: 78, height: 78)
                .clipShape(Circle())
                .overlay { Circle().stroke(Color.white.opacity(0.12), lineWidth: 1) }

                PhotosPicker(selection: $selectedProfilePhoto, matching: .images) {
                    ZStack {
                        Circle().fill(HaloTheme.lime).frame(width: 30, height: 30)
                        if profilePhotoBusy { ProgressView().tint(HaloTheme.ink).scaleEffect(0.7) }
                        else { Image(systemName: "camera.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(HaloTheme.ink) }
                    }
                }
                .disabled(profilePhotoBusy)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(profileName).font(HaloType.display(23, weight: .semibold)).foregroundStyle(.white)
                Text("HALO FIELD").font(HaloType.body(9, weight: .bold)).tracking(1.5).foregroundStyle(HaloTheme.lime)
#if DEBUG
                Text(HaloBuildStamp.revision)
                    .font(HaloType.body(8, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(HaloTheme.actionBlue)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 22)
                    .background(HaloTheme.actionBlue.opacity(0.10), in: Capsule())
#endif
                Text("Private crew identity on this organization's field network.")
                    .font(HaloType.body(10, weight: .medium)).foregroundStyle(.white.opacity(0.42))
            }
            Spacer()
        }
        .padding(18)
        .haloDarkCard()
        .overlay(alignment: .bottomLeading) {
            if let profilePhotoError {
                Text(profilePhotoError).font(HaloType.body(9, weight: .semibold)).foregroundStyle(HaloTheme.warning).padding(.horizontal, 18).offset(y: 18)
            }
        }
    }

    private func settingRow(icon: String, title: String, subtitle: String, tint: Color, trailing: String? = nil, badge: String? = nil) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(tint.opacity(0.11)).frame(width: 44, height: 44)
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(HaloType.body(14, weight: .bold)).foregroundStyle(.white)
                Text(subtitle).font(HaloType.body(10, weight: .medium)).foregroundStyle(.white.opacity(0.40)).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            if let badge { HaloStatusPill(text: badge, tint: tint) }
            if let trailing { Image(systemName: trailing).font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.25)) }
        }
        .padding(15)
        .haloDarkCard()
    }

    @MainActor
    private func loadProfilePhoto() async {
        guard let token = session.activationToken, !token.isEmpty else { return }
        do {
            let profile = try await HaloAPI.shared.fetchProfilePhoto(activationToken: token)
            profileName = profile.name.isEmpty ? "Crew profile" : profile.name
            profilePhotoURL = profile.url
            profilePhotoError = nil
        } catch { profilePhotoError = error.localizedDescription }
    }

    @MainActor
    private func uploadProfilePhoto(_ item: PhotosPickerItem) async {
        guard let token = session.activationToken, !token.isEmpty else { return }
        profilePhotoBusy = true
        defer { profilePhotoBusy = false; selectedProfilePhoto = nil }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: raw),
                  let jpeg = image.jpegData(compressionQuality: 0.88) else {
                profilePhotoError = "That photo could not be loaded."; return
            }
            guard jpeg.count <= 5 * 1024 * 1024 else { profilePhotoError = "Profile photo must be 5 MB or smaller."; return }
            let profile = try await HaloAPI.shared.uploadProfilePhoto(imageData: jpeg, activationToken: token)
            profilePhotoURL = profile.url
            profilePhotoError = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            profilePhotoError = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
