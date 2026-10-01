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
            (2, "Halo", "sparkles")
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
                .font(HaloType.body(9, weight: .semibold))
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

            Text("HALO")
                .font(HaloType.body(8, weight: .bold))
                .tracking(0.35)
                .foregroundStyle(selected ? HaloTheme.lime : .white.opacity(0.48))
        }
        .frame(maxWidth: .infinity, minHeight: HaloTheme.minimumTapTarget)
        .offset(y: -2)
        .contentShape(Rectangle())
    }
}


private struct ManagerLiveView: View {
    @EnvironmentObject private var session: HaloSessionStore
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var realtime: HaloRealtimeService
    @State private var snapshot: HaloManagerLiveSnapshot?
    @State private var selectedCrewID: String?
    @State private var selectedProperty = "All properties"
    @State private var selectedState = "Active"
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var filtersExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var locations: [HaloManagerCrewLocation] {
        guard let snapshot else { return [] }
        return snapshot.locations.filter { location in
            let propertyMatch = selectedProperty == "All properties" || location.property == selectedProperty
            let stateMatch: Bool
            switch selectedState {
            case "Live": stateMatch = location.locationState == "live"
            case "Recent": stateMatch = location.locationState.hasPrefix("recent")
            case "On clock": stateMatch = ["checked_in", "paused", "lunch"].contains(location.status)
            case "Needs attention": stateMatch = !["live", "recent", "recent_verified"].contains(location.locationState)
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
                                withAnimation(HaloMotion.animation(reduceMotion: reduceMotion)) {
                                    selectedCrewID = location.crewID
                                    cameraPosition = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lng), span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)))
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                VStack(spacing: 4) {
                                    ZStack {
                                        if location.locationState == "live" {
                                            HaloPulseRing(tint: HaloTheme.lime).frame(width: 58, height: 58)
                                        }
                                        Circle()
                                            .fill(location.locationState == "live" ? HaloTheme.lime : Color.white)
                                            .frame(width: selectedCrewID == location.crewID ? 54 : 48, height: selectedCrewID == location.crewID ? 54 : 48)
                                            .shadow(color: location.locationState == "live" ? HaloTheme.lime.opacity(0.18) : .black.opacity(0.28), radius: 10, y: 4)
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
                                        .frame(width: selectedCrewID == location.crewID ? 46 : 40, height: selectedCrewID == location.crewID ? 46 : 40)
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
            while !Task.isCancelled {
                let fallbackSeconds: Double = realtime.state == .connected ? 300 : 15
                try? await Task.sleep(for: .seconds(fallbackSeconds))
                if network.isConnected { await refresh() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .haloDataInvalidated)) { note in
            guard network.isConnected else { return }
            if let payload = note.object as? [String: Any],
               let scopes = payload["scopes"] as? [String],
               !scopes.contains("live") {
                return
            }
            Task { await refresh() }
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
        VStack(spacing: 9) {
            HStack(spacing: 9) {
                Button {
                    withAnimation(HaloMotion.animation(reduceMotion: reduceMotion)) { filtersExpanded.toggle() }
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                        Text(selectedProperty == "All properties" && selectedState == "Active" ? "Filter live map" : "\(selectedProperty) · \(selectedState)")
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(filtersExpanded ? 180 : 0))
                    }
                    .font(HaloType.body(10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 13)
                    .frame(height: 42)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    cameraPosition = .automatic
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }

                Button { Task { await refresh() } } label: {
                    Image(systemName: isLoading ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .disabled(isLoading || !network.isConnected)
            }

            if filtersExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text("PROPERTY").font(HaloType.body(8, weight: .bold)).tracking(1.2).foregroundStyle(.white.opacity(0.34))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(properties, id: \.self) { property in
                                mapFilterChoice(property, selected: selectedProperty == property) {
                                    selectedProperty = property; selectedCrewID = nil
                                }
                            }
                        }
                    }
                    Text("STATUS").font(HaloType.body(8, weight: .bold)).tracking(1.2).foregroundStyle(.white.opacity(0.34))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(["Active", "Live", "Recent", "On clock", "Needs attention"], id: \.self) { state in
                                mapFilterChoice(state, selected: selectedState == state) {
                                    selectedState = state; selectedCrewID = nil
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let errorMessage {
                Text(errorMessage).font(HaloType.body(10, weight: .medium)).foregroundStyle(HaloTheme.warning).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
    }

    private func mapFilterChoice(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(HaloMotion.animation(reduceMotion: reduceMotion, duration: 0.22)) { action() }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Text(text)
                .font(HaloType.body(9, weight: .bold))
                .foregroundStyle(selected ? HaloTheme.ink : .white.opacity(0.60))
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(selected ? HaloTheme.lime : Color.white.opacity(0.055), in: Capsule())
        }
        .buttonStyle(.plain)
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

    private func locationStateLabel(_ state: String) -> String {
        switch state {
        case "live": "LIVE"
        case "recent": "RECENT"
        case "recent_verified": "VERIFIED RECENT"
        case "permission_required": "PERMISSION NEEDED"
        case "background_stopped": "BACKGROUND OFF"
        case "sharing_stopped": "SHARING STOPPED"
        case "expired": "EXPIRED"
        default: "LOCATION UNAVAILABLE"
        }
    }

    private func locationStateColor(_ state: String) -> Color {
        switch state {
        case "live": HaloTheme.lime
        case "permission_required", "background_stopped": HaloTheme.warning
        default: .white.opacity(0.55)
        }
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
                    Text(locationStateLabel(crew.locationState))
                        .font(HaloType.body(8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(locationStateColor(crew.locationState))
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
        .transition(.asymmetric(insertion: .scale(scale: 0.94, anchor: .bottom).combined(with: .opacity), removal: .opacity))
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
                            .buttonStyle(HaloPressableStyle())
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
