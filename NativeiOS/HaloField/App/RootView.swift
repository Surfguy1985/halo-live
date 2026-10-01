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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        appearance.backgroundColor = UIColor(red: 9/255, green: 23/255, blue: 34/255, alpha: 0.72)
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.06)

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().unselectedItemTintColor = UIColor.white.withAlphaComponent(0.42)
    }

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
        }
        .task(id: network.isConnected) {
            guard network.isConnected else {
                fieldSync.refreshPendingCount(context: modelContext, activationToken: session.activationToken)
                return
            }
            await fieldSync.flush(context: modelContext, activationToken: session.activationToken)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            fieldSync.refreshPendingCount(context: modelContext, activationToken: session.activationToken)
            if network.isConnected {
                await fieldSync.flush(context: modelContext, activationToken: session.activationToken)
            }
        }
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
            }
        }
    }

    private var tabShell: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { TodayView() }
                .tabItem { Label("Today", systemImage: "bolt.fill") }
                .tag(0)

            NavigationStack { JobsView() }
                .tabItem { Label("Jobs", systemImage: "square.stack.3d.up.fill") }
                .tag(1)

            NavigationStack { HaloCommsView() }
                .tabItem { Label("Halo", systemImage: "sparkles") }
                .tag(2)

            if session.managerLiveAccess {
                NavigationStack { ManagerLiveView() }
                    .tabItem { Label("Live", systemImage: "map.fill") }
                    .tag(3)
            }

            NavigationStack { ProfileView() }
                .tabItem { Label("Me", systemImage: "person.crop.circle") }
                .tag(4)
        }
        .tint(HaloTheme.lime)
    }
}


private struct ManagerLiveView: View {
    @EnvironmentObject private var session: HaloSessionStore
    @EnvironmentObject private var network: NetworkMonitor
    @State private var snapshot: HaloManagerLiveSnapshot?
    @State private var selectedCrewID: String?
    @State private var selectedProperty = "All properties"
    @State private var selectedState = "Active"
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var locations: [HaloManagerCrewLocation] {
        guard let snapshot else { return [] }
        return snapshot.locations.filter { location in
            let propertyMatch = selectedProperty == "All properties" || location.property == selectedProperty
            let stateMatch: Bool
            switch selectedState {
            case "Live": stateMatch = location.locationState == "live"
            case "Recent": stateMatch = location.locationState.hasPrefix("recent")
            case "On clock": stateMatch = ["checked_in", "paused", "lunch"].contains(location.status)
            default: stateMatch = location.locationState == "live" || location.locationState.hasPrefix("recent")
            }
            return propertyMatch && stateMatch
        }
    }

    private var mappedLocations: [HaloManagerCrewLocation] {
        locations.filter { $0.latitude != nil && $0.longitude != nil }
    }

    private var properties: [String] {
        ["All properties"] + Array(Set((snapshot?.locations ?? []).map(\.property).filter { !$0.isEmpty })).sorted()
    }

    private var selectedCrew: HaloManagerCrewLocation? {
        locations.first(where: { $0.crewID == selectedCrewID })
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition) {
                ForEach(mappedLocations) { location in
                    if let lat = location.latitude, let lng = location.longitude {
                        Annotation(location.crewName, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng), anchor: .bottom) {
                            Button {
                                selectedCrewID = location.crewID
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        Circle()
                                            .fill(location.locationState == "live" ? HaloTheme.lime : Color.white)
                                            .frame(width: 48, height: 48)
                                            .shadow(color: .black.opacity(0.28), radius: 8, y: 4)
                                        AsyncImage(url: location.photoURL.flatMap(URL.init(string:))) { phase in
                                            switch phase {
                                            case .success(let image):
                                                image.resizable().scaledToFill()
                                            default:
                                                Text(initials(location.crewName))
                                                    .font(HaloType.body(11, weight: .bold))
                                                    .foregroundStyle(HaloTheme.ink)
                                            }
                                        }
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())
                                    }
                                    Text(location.unitNumber.isEmpty ? location.crewName : "Unit \(location.unitNumber)")
                                        .font(HaloType.body(9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.black.opacity(0.75), in: Capsule())
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 10) {
                managerHeader

                if let selectedCrew {
                    selectedCrewCard(selectedCrew)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(HaloTheme.fieldBackground)
        .navigationTitle("Live Operations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            filterBar
        }
        .task(id: session.activationToken) {
            await refresh()
        }
        .task(id: network.isConnected) {
            guard network.isConnected else { return }
            await refresh()
        }
        .refreshable {
            await refresh()
        }
    }

    private var filterBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(properties, id: \.self) { property in
                        Button(property) { selectedProperty = property; selectedCrewID = nil }
                    }
                } label: {
                    filterPill(icon: "building.2.fill", text: selectedProperty)
                }

                Menu {
                    ForEach(["Active", "Live", "Recent", "On clock"], id: \.self) { state in
                        Button(state) { selectedState = state; selectedCrewID = nil }
                    }
                } label: {
                    filterPill(icon: "line.3.horizontal.decrease.circle.fill", text: selectedState)
                }

                Spacer(minLength: 4)

                Button {
                    Task { await refresh() }
                } label: {
                    Image(systemName: isLoading ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .disabled(isLoading || !network.isConnected)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(HaloType.body(10, weight: .medium))
                    .foregroundStyle(HaloTheme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var managerHeader: some View {
        let summary = snapshot?.summary
        return HStack(spacing: 8) {
            metric(value: summary?.live ?? 0, label: "LIVE")
            metric(value: summary?.onClock ?? 0, label: "ON CLOCK")
            metric(value: summary?.activeUnits ?? 0, label: "UNITS")
            metric(value: summary?.properties ?? 0, label: "PROPERTIES")
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func metric(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(HaloType.display(19, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .font(HaloType.body(7, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
    }

    private func selectedCrewCard(_ crew: HaloManagerCrewLocation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AsyncImage(url: crew.photoURL.flatMap(URL.init(string:))) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default:
                        ZStack {
                            Circle().fill(Color.white.opacity(0.08))
                            Text(initials(crew.crewName))
                                .font(HaloType.body(13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(crew.crewName)
                            .font(HaloType.body(15, weight: .bold))
                            .foregroundStyle(.white)
                        if crew.identityVerifiedToday {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(HaloTheme.lime)
                        }
                    }
                    Text([crew.property, crew.unitNumber.isEmpty ? nil : "Unit \(crew.unitNumber)"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(HaloType.body(11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(crew.locationState == "live" ? "LIVE" : "RECENT")
                        .font(HaloType.body(8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(crew.locationState == "live" ? HaloTheme.lime : .white.opacity(0.55))
                    if let accuracy = crew.accuracy {
                        Text("±\(Int(accuracy.rounded()))m")
                            .font(HaloType.body(9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.38))
                    }
                }
            }

            if !crew.services.isEmpty {
                Text(crew.services.prefix(4).joined(separator: " · "))
                    .font(HaloType.body(10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button {
                    NotificationCenter.default.post(
                        name: .haloOpenComms,
                        object: ["channel": "dm:crew:\(crew.crewID)", "category": "message"]
                    )
                } label: {
                    actionButton(icon: "message.fill", text: "Message")
                }

                if !crew.unitID.isEmpty {
                    Button {
                        NotificationCenter.default.post(name: .haloOpenJob, object: crew.unitID)
                    } label: {
                        actionButton(icon: "square.stack.3d.up.fill", text: "Open unit")
                    }
                }

                Button {
                    selectedCrewID = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.08))
        }
    }

    private func actionButton(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(HaloType.body(10, weight: .bold))
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .foregroundStyle(HaloTheme.ink)
            .background(HaloTheme.lime, in: Capsule())
    }

    private func filterPill(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text).lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .font(HaloType.body(10, weight: .bold))
        .foregroundStyle(.white.opacity(0.82))
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Color.white.opacity(0.07), in: Capsule())
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    @MainActor
    private func refresh() async {
        guard let token = session.activationToken, !token.isEmpty, network.isConnected else {
            if !network.isConnected { errorMessage = "Live Operations needs a connection. Field work remains available offline." }
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let next = try await HaloAPI.shared.fetchManagerLive(activationToken: token)
            snapshot = next
            errorMessage = nil
            if selectedCrewID != nil && !next.locations.contains(where: { $0.crewID == selectedCrewID }) {
                selectedCrewID = nil
            }
            if next.locations.contains(where: { $0.latitude != nil && $0.longitude != nil }) {
                cameraPosition = .automatic
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct JobsView: View {
    @EnvironmentObject var store: JobStore
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                TurnsPickupView()

                if !store.jobs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("MY JOBS")
                                .font(HaloType.body(9, weight: .bold))
                                .tracking(1.6)
                                .foregroundStyle(.white.opacity(0.38))
                            Spacer()
                            Text("\(store.activeJobCount) active")
                                .font(HaloType.body(10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.42))
                        }

                        ForEach(store.jobs) { job in
                            NavigationLink { JobDetailView(jobID: job.id) } label: {
                                FieldJobCard(job: job, hero: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(HaloTheme.fieldBackground.ignoresSafeArea())
        .navigationTitle("Jobs")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(isPresented: Binding(
            get: { store.selectedJobID != nil },
            set: { if !$0 { store.selectedJobID = nil } }
        )) {
            if let jobID = store.selectedJobID {
                JobDetailView(jobID: jobID)
            }
        }
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
        case .notDetermined: .secondary
        @unknown default: .secondary
        }
    }

    var body: some View {
        List {
            Section("Field") {
                NavigationLink {
                    SyncIssuesView()
                } label: {
                    HStack {
                        Label(network.isConnected ? "Field sync" : "Offline mode", systemImage: network.isConnected ? "arrow.triangle.2.circlepath" : "wifi.slash")
                        Spacer()
                        Text(fieldSync.attentionCount > 0
                             ? "\(fieldSync.attentionCount) need attention"
                             : (fieldSync.pendingCount == 0 ? "Up to date" : "\(fieldSync.pendingCount) pending"))
                            .font(.caption)
                            .foregroundStyle(fieldSync.pendingCount == 0 && fieldSync.attentionCount == 0 ? HaloTheme.fieldLive : HaloTheme.warning)
                    }
                }
                Label("Location verification", systemImage: "location.fill")

                Button {
                    if notifications.authorizationStatus == .denied {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
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
                    HStack {
                        Label("Notifications", systemImage: "bell.fill")
                        Spacer()
                        Text(notificationStatusText)
                            .font(.caption)
                            .foregroundStyle(notificationStatusColor)
                    }
                }
                .buttonStyle(.plain)
            }
            Section("Account") {
                HStack(spacing: 14) {
                    AsyncImage(url: profilePhotoURL.flatMap(URL.init(string:))) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            ZStack {
                                Circle().fill(Color.white.opacity(0.08))
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 34))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                        }
                    }
                    .frame(width: 58, height: 58)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(profileName)
                            .font(HaloType.body(14, weight: .bold))
                        Text("Private crew portrait")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    PhotosPicker(selection: $selectedProfilePhoto, matching: .images) {
                        if profilePhotoBusy {
                            ProgressView()
                        } else {
                            Label("Edit", systemImage: "camera.fill")
                                .font(HaloType.body(10, weight: .bold))
                        }
                    }
                    .disabled(profilePhotoBusy)
                }

                if let profilePhotoError {
                    Text(profilePhotoError)
                        .font(.caption)
                        .foregroundStyle(HaloTheme.warning)
                }

                Label("Settings", systemImage: "gearshape.fill")
                Button(role: .destructive) {
                    let token = session.activationToken
                    Task {
                        await notifications.unregisterRemoteDevice(activationToken: token)
                    }
                    store.clear(removeCache: true)
                    session.deactivate()
                } label: {
                    Label("Deactivate this iPhone", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(fieldSync.pendingCount > 0 || fieldSync.attentionCount > 0)

                if fieldSync.pendingCount > 0 || fieldSync.attentionCount > 0 {
                    Text("Sync or resolve saved field work before deactivating this iPhone.")
                        .font(.caption)
                        .foregroundStyle(HaloTheme.warning)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(HaloTheme.fieldBackground)
        .navigationTitle("Me")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: session.activationToken) {
            await loadProfilePhoto()
        }
        .onChange(of: selectedProfilePhoto) { _, item in
            guard let item else { return }
            Task { await uploadProfilePhoto(item) }
        }
    }

    @MainActor
    private func loadProfilePhoto() async {
        guard let token = session.activationToken, !token.isEmpty else { return }
        do {
            let profile = try await HaloAPI.shared.fetchProfilePhoto(activationToken: token)
            profileName = profile.name.isEmpty ? "Crew profile" : profile.name
            profilePhotoURL = profile.url
            profilePhotoError = nil
        } catch {
            profilePhotoError = error.localizedDescription
        }
    }

    @MainActor
    private func uploadProfilePhoto(_ item: PhotosPickerItem) async {
        guard let token = session.activationToken, !token.isEmpty else { return }
        profilePhotoBusy = true
        defer {
            profilePhotoBusy = false
            selectedProfilePhoto = nil
        }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: raw),
                  let jpeg = image.jpegData(compressionQuality: 0.88) else {
                profilePhotoError = "That photo could not be loaded."
                return
            }
            guard jpeg.count <= 5 * 1024 * 1024 else {
                profilePhotoError = "Profile photo must be 5 MB or smaller."
                return
            }
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