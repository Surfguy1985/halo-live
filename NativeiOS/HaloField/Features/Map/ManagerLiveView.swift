import MapKit
import SwiftUI

struct ManagerLiveView: View {
    @EnvironmentObject private var session: HaloSessionStore
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var realtime: HaloRealtimeService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var snapshot: HaloManagerLiveSnapshot?
    @State private var selectedCrewID: String?
    @State private var property = "All properties"
    @State private var filter = "All crews"
    @State private var search = ""
    @State private var camera: MapCameraPosition = .automatic
    @State private var satellite = false
    @State private var showFences = true
    @State private var followCrew = false
    @State private var loading = false
    @State private var error: String?
    @State private var lastRefresh: Date?
    @State private var requestID = UUID()
    @State private var openedJob: FieldJob?
    @State private var openingJob = false
    @State private var selectedCluster: HaloCrewCluster?

    private var fences: [HaloMapGeofence] {
        (snapshot?.geofences ?? []).filter { property == "All properties" || $0.name == property }
    }
    private var properties: [String] {
        ["All properties"] + Array(Set((snapshot?.geofences.map(\.name) ?? []) + (snapshot?.locations.map(\.property) ?? []))).filter { !$0.isEmpty }.sorted()
    }
    private var selected: HaloManagerCrewLocation? { snapshot?.locations.first { $0.crewID == selectedCrewID } }
    private func fence(for crew: HaloManagerCrewLocation) -> HaloMapGeofence? {
        snapshot?.geofences.first { $0.name.caseInsensitiveCompare(crew.property) == .orderedSame }
    }
    private func rows(at now: Date) -> [HaloManagerCrewLocation] {
        (snapshot?.locations ?? []).filter { crew in
            let state = crew.displayState(at: now)
            let matches: Bool
            switch filter {
            case "Live": matches = state == "live"
            case "On clock": matches = ["checked_in", "paused", "lunch"].contains(crew.status)
            case "Outside fence": matches = fence(for: crew)?.assessment(for: crew, now: now) == .outside
            case "Needs GPS": matches = crew.mapCoordinate(at: now) == nil
            default: matches = true
            }
            let text = [crew.crewName, crew.property, crew.unitNumber].joined(separator: " ")
            return matches && (property == "All properties" || crew.property == property)
                && (search.isEmpty || text.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        Group {
            if session.managerLiveAccess {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    mapScreen(now: context.date)
                }
            } else {
                ContentUnavailableView("Office access required", systemImage: "lock.shield")
            }
        }
        .navigationTitle("Live Operations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $openedJob) { job in
            NavigationStack { JobRecordView(job: job).toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { openedJob = nil } }
            } }
        }
        .sheet(item: $selectedCluster) { cluster in
            NavigationStack {
                List(cluster.crews) { crew in
                    Button {
                        selectedCluster = nil
                        select(crew, now: .now)
                    } label: {
                        HStack(spacing: 12) {
                            CrewMapAvatar(crew: crew, size: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(crew.crewName).font(.headline).foregroundStyle(.white)
                                Text("Unit \(crew.unitNumber) · \(stateLabel(crew.displayState(at: .now)))")
                                    .font(.caption).foregroundStyle(HaloTheme.lime)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }.padding(.vertical, 5)
                    }
                }.navigationTitle("\(cluster.crews.count) crews here")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selectedCluster = nil } } }
            }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .task(id: session.activationToken) {
            snapshot = nil; selectedCrewID = nil; lastRefresh = nil
            await refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(realtime.state == .connected ? 30 : 15)) }
                catch { break }
                guard scenePhase == .active else { continue }
                await refresh()
            }
        }
        .onChange(of: session.managerLiveAccess) { _, allowed in
            if !allowed { requestID = UUID(); snapshot = nil; selectedCrewID = nil; openedJob = nil; selectedCluster = nil; loading = false }
        }
        .onChange(of: network.isConnected) { _, connected in
            if connected { Task { await refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .haloDataInvalidated)) { note in
            if let payload = note.object as? [String: Any], let scopes = payload["scopes"] as? [String],
               !scopes.contains("live") && !scopes.contains("jobs") { return }
            Task { await refresh() }
        }
    }

    private func mapScreen(now: Date) -> some View {
        Map(position: $camera) { mapLayers(now: now) }
            .mapStyle(satellite ? .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll) : .standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .mapControls { MapCompass(); MapScaleView() }
            .onMapCameraChange(frequency: .onEnd) { _ in
                if camera.positionedByUser { followCrew = false }
            }
            .safeAreaInset(edge: .top, spacing: 0) { topBar(now: now) }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomPanel(now: now) }
            .overlay(alignment: .topTrailing) { mapControls.padding(.top, 12).padding(.trailing, 12) }
    }

    @MapContentBuilder private func mapLayers(now: Date) -> some MapContent {
        if showFences {
            ForEach(fences) { zone in
                MapCircle(center: zone.coordinate, radius: zone.radiusMeters)
                    .foregroundStyle(HaloTheme.actionBlue.opacity(0.12))
                    .stroke(HaloTheme.actionBlue.opacity(0.75), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                Annotation(zone.name, coordinate: zone.coordinate, anchor: .center) {
                    Button {
                        property = zone.name; selectedCrewID = nil; followCrew = false
                        focus(zone.coordinate, meters: zone.radiusMeters * 5)
                    } label: {
                        Image(systemName: "building.2.fill").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white).frame(width: 44, height: 44)
                            .background(HaloTheme.actionBlue, in: RoundedRectangle(cornerRadius: 13))
                            .overlay { RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.55), lineWidth: 2) }
                    }.buttonStyle(.plain).accessibilityLabel("\(zone.name), \(Int(zone.radiusMeters)) meter arrival geofence")
                }.annotationTitles(.hidden)
            }
        }
        if let crew = selected, let point = crew.mapCoordinate(at: now), let accuracy = crew.accuracy,
           accuracy.isFinite, accuracy > 0, accuracy < 5000 {
            MapCircle(center: point, radius: accuracy)
                .foregroundStyle(HaloTheme.lime.opacity(0.10)).stroke(HaloTheme.lime.opacity(0.35), lineWidth: 1)
        }
        ForEach(HaloCrewCluster.group(rows(at: now), at: now)) { cluster in
            Annotation(cluster.crews.count > 1 ? "\(cluster.crews.count) crews" : cluster.crews[0].crewName, coordinate: cluster.coordinate, anchor: .bottom) {
                if cluster.crews.count > 1 {
                    Button { selectedCluster = cluster } label: {
                        VStack(spacing: 2) {
                            HStack(spacing: -12) {
                                ForEach(Array(cluster.crews.prefix(3))) { crew in
                                    CrewMapAvatar(crew: crew, size: 36).overlay { Circle().stroke(HaloTheme.fieldChrome, lineWidth: 3) }
                                }
                                Text("\(cluster.crews.count)").font(.caption.weight(.heavy)).foregroundStyle(HaloTheme.ink)
                                    .frame(width: 28, height: 28).background(HaloTheme.lime, in: Circle()).padding(.leading, 14)
                            }.padding(8).background(HaloTheme.fieldChrome, in: Capsule())
                                .overlay { Capsule().stroke(HaloTheme.lime, lineWidth: 2) }
                            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 10)).foregroundStyle(HaloTheme.lime)
                        }
                    }.buttonStyle(.plain).accessibilityLabel("\(cluster.crews.count) crews at this location. Show crew list.")
                } else {
                    let crew = cluster.crews[0]
                    Button { select(crew, now: now) } label: {
                        CrewMapBubble(crew: crew, state: crew.displayState(at: now), selected: selectedCrewID == crew.crewID)
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(crew.crewName), \(stateLabel(crew.displayState(at: now))), \(crew.property), unit \(crew.unitNumber)")
                }
            }.annotationTitles(.hidden)
        }
    }

    private func topBar(now: Date) -> some View {
        VStack(spacing: 10) {
            HStack {
                HaloLogo(height: 20)
                Text("LIVE OPERATIONS").font(.system(size: 9, weight: .bold)).tracking(1.4).foregroundStyle(.white.opacity(0.55))
                Spacer()
                if loading { ProgressView().tint(HaloTheme.lime) }
                Circle().fill(network.isConnected && error == nil ? HaloTheme.lime : HaloTheme.warning).frame(width: 6, height: 6)
                Text(network.isConnected ? "Online" : "Offline").font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(HaloTheme.muted)
                TextField("Find crew, property or unit", text: $search).font(.subheadline).textInputAutocapitalization(.never).autocorrectionDisabled()
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear search") }
            }.padding(.horizontal, 12).frame(minHeight: 44).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            HStack {
                Menu {
                    ForEach(properties, id: \.self) { name in
                        Button(name) { property = name; selectedCrewID = nil; followCrew = false; camera = .automatic }
                    }
                } label: { Label(property, systemImage: "building.2").lineLimit(1) }
                Spacer()
                Menu {
                    ForEach(["All crews", "Live", "On clock", "Outside fence", "Needs GPS"], id: \.self) { name in
                        Button(name) { filter = name; selectedCrewID = nil; followCrew = false }
                    }
                } label: { Label(filter, systemImage: "line.3.horizontal.decrease") }
            }.font(.caption.weight(.semibold)).tint(HaloTheme.lime).frame(minHeight: 30)
            if let error { Text(error).font(.caption).foregroundStyle(HaloTheme.warning).frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(14).background(.ultraThinMaterial).background(HaloTheme.fieldChrome.opacity(0.8))
    }

    private var mapControls: some View {
        VStack(spacing: 8) {
            mapButton(satellite ? "map" : "globe.americas.fill", label: "Toggle satellite map", selected: satellite) { satellite.toggle() }
            mapButton("circle.dashed", label: "Toggle arrival geofences", selected: showFences) { showFences.toggle() }
            mapButton("scope", label: "Fit all visible crews and properties", selected: false) { followCrew = false; camera = .automatic }
            mapButton("arrow.clockwise", label: "Refresh live locations", selected: false) { Task { await refresh() } }.disabled(loading || !network.isConnected)
        }.padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 19))
    }
    private func mapButton(_ icon: String, label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 44)
                .foregroundStyle(selected ? HaloTheme.ink : .white)
                .background(selected ? HaloTheme.lime : .clear, in: RoundedRectangle(cornerRadius: 13))
        }.buttonStyle(HaloPressableStyle()).accessibilityLabel(label).accessibilityValue(selected ? "On" : "Off")
    }

    private func bottomPanel(now: Date) -> some View {
        VStack(spacing: 10) {
            if let crew = selected { crewCard(crew, now: now) }
            else {
                let visible = rows(at: now)
                HStack {
                    Text("\(visible.filter { $0.displayState(at: now) == "live" }.count) live")
                        .foregroundStyle(HaloTheme.lime)
                    Text("· \(visible.count) crews").foregroundStyle(.white.opacity(0.65))
                    Spacer()
                    if let lastRefresh { Text(lastRefresh, style: .relative).foregroundStyle(.white.opacity(0.5)) }
                }.font(.caption.weight(.semibold))
                if visible.isEmpty {
                    Text(loading ? "Locating your team…" : "No crews match this view. Try another filter.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.65)).padding(.vertical, 10)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(visible) { crew in
                                Button { select(crew, now: now) } label: {
                                    HStack(spacing: 9) {
                                        CrewMapAvatar(crew: crew, size: 36)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(crew.crewName).font(.caption.weight(.bold)).foregroundStyle(.white)
                                            Text(stateLabel(crew.displayState(at: now))).font(.caption2).foregroundStyle(tint(crew.displayState(at: now)))
                                        }
                                    }.padding(10).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 17))
                                }.buttonStyle(HaloPressableStyle())
                            }
                        }
                    }
                }
                Label(showFences ? "Blue rings · arrival geofences" : "Arrival geofences hidden", systemImage: "circle.dashed")
                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
            }
        }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.10)) }
            .padding(10)
    }

    private func crewCard(_ crew: HaloManagerCrewLocation, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CrewMapAvatar(crew: crew, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(crew.crewName).font(.headline).foregroundStyle(.white)
                    Text("\(crew.property) · Unit \(crew.unitNumber.isEmpty ? "—" : crew.unitNumber)")
                        .font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
                }
                Spacer()
                Button { selectedCrewID = nil; followCrew = false } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }.accessibilityLabel("Close crew details")
            }
            HStack {
                HaloStatusPill(text: stateLabel(crew.displayState(at: now)), tint: tint(crew.displayState(at: now)))
                if let date = crew.capturedDate { Text(date, style: .relative).font(.caption2).foregroundStyle(.white.opacity(0.65)) }
                Spacer()
                if let accuracy = crew.accuracy, accuracy.isFinite, accuracy >= 0, accuracy < 100000 {
                    Text("±\(Int(accuracy)) m").font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.65))
                }
            }
            if let zone = fence(for: crew) {
                let status = zone.assessment(for: crew, now: now)
                Label("\(status.rawValue) · \(Int(zone.radiusMeters)) m", systemImage: status == .inside ? "checkmark.shield.fill" : "circle.dashed")
                    .font(.caption.weight(.semibold)).foregroundStyle(status == .outside ? HaloTheme.warning : HaloTheme.lime)
            } else {
                Label("No arrival geofence configured", systemImage: "circle.dashed").font(.caption).foregroundStyle(.secondary)
            }
            Text("\(crew.status.replacingOccurrences(of: "_", with: " ").capitalized) · \(max(0, crew.workedMs) / 3600000)h \((max(0, crew.workedMs) / 60000) % 60)m recorded")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 8) {
                Button {
                    NotificationCenter.default.post(name: .haloOpenComms, object: ["channel": "dm:crew:\(crew.crewID)", "category": "message"])
                } label: { Label("Message", systemImage: "message.fill") }
                Button {
                    followCrew.toggle()
                    if let point = crew.mapCoordinate(at: now) { focus(point) }
                } label: { Label(followCrew ? "Following" : "Follow", systemImage: "location.fill") }
                    .disabled(crew.mapCoordinate(at: now) == nil)
                if !crew.unitID.isEmpty {
                    Button { Task { await openUnit(crew.unitID) } } label: { Label(openingJob ? "Loading" : "Unit", systemImage: "square.stack.3d.up") }
                        .disabled(openingJob)
                }
            }.font(.caption.weight(.bold)).buttonStyle(.bordered).tint(HaloTheme.lime).controlSize(.regular)
            Text("Arrival boundary is a live estimate; clock-in verification remains server controlled.")
                .font(.caption2).foregroundStyle(.white.opacity(0.45))
        }
    }

    private func select(_ crew: HaloManagerCrewLocation, now: Date) {
        withAnimation(HaloMotion.animation(reduceMotion: reduceMotion)) { selectedCrewID = crew.crewID }
        followCrew = false
        if let point = crew.mapCoordinate(at: now) { focus(point) }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
    private func focus(_ point: CLLocationCoordinate2D, meters: Double = 1800) {
        withAnimation(HaloMotion.animation(reduceMotion: reduceMotion)) {
            camera = .region(MKCoordinateRegion(center: point, latitudinalMeters: max(800, meters), longitudinalMeters: max(800, meters)))
        }
    }
    private func stateLabel(_ state: String) -> String {
        switch state {
        case "live": "Live GPS"
        case "recent": "Recent GPS"
        case "recent_verified": "Recent check-in"
        case "sharing_stopped": "Sharing off"
        case "permission_required": "Permission needed"
        case "background_stopped": "GPS stopped"
        case "expired": "GPS expired"
        default: "GPS unavailable"
        }
    }
    private func tint(_ state: String) -> Color { state == "live" ? HaloTheme.lime : state.hasPrefix("recent") ? HaloTheme.warning : .white.opacity(0.55) }

    @MainActor private func refresh() async {
        guard session.managerLiveAccess, let token = session.activationToken, network.isConnected, !loading else { return }
        let id = UUID(); requestID = id; loading = true
        defer { if requestID == id { loading = false } }
        do {
            let next = try await HaloAPI.shared.fetchManagerLive(activationToken: token)
            guard !Task.isCancelled, requestID == id, session.activationToken == token, session.managerLiveAccess else { return }
            let initial = snapshot == nil
            snapshot = next; error = nil; lastRefresh = .now
            if initial { camera = .automatic }
            if let selectedCrewID, !next.locations.contains(where: { $0.crewID == selectedCrewID }) { self.selectedCrewID = nil; followCrew = false }
            if followCrew, let point = selected?.mapCoordinate(at: .now) { focus(point) }
        } catch {
            guard !Task.isCancelled, session.activationToken == token, requestID == id else { return }
            self.error = "Live locations could not refresh. Showing the last received update."
        }
    }
    @MainActor private func openUnit(_ id: String) async {
        guard session.officeAccess, let token = session.activationToken else { return }
        openingJob = true
        defer { openingJob = false }
        do {
            let jobs = try await HaloAPI.shared.fetchJobs(activationToken: token, scope: "board")
            guard session.officeAccess, session.activationToken == token else { return }
            openedJob = jobs.first { $0.id == id }
            if openedJob == nil { error = "This unit is no longer on the open board." }
        } catch { self.error = error.localizedDescription }
    }
}

private struct CrewMapAvatar: View {
    let crew: HaloManagerCrewLocation
    let size: CGFloat
    var body: some View {
        AsyncImage(url: crew.photoURL.flatMap(URL.init(string:))) { phase in
            if let image = phase.image { image.resizable().scaledToFill() }
            else { ZStack { HaloTheme.fieldChrome; Text(crew.initials).font(.system(size: size * 0.3, weight: .bold)).foregroundStyle(.white) } }
        }.frame(width: size, height: size).clipShape(Circle())
    }
}

private struct CrewMapBubble: View {
    let crew: HaloManagerCrewLocation
    let state: String
    let selected: Bool
    private var color: Color { state == "live" ? HaloTheme.lime : HaloTheme.warning }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                ZStack {
                    if state == "live" && selected { HaloPulseRing(tint: color).frame(width: 42, height: 42) }
                    CrewMapAvatar(crew: crew, size: selected ? 44 : 36)
                        .overlay { Circle().stroke(color, lineWidth: 2) }
                }
                if selected {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(crew.crewName).font(.caption.weight(.bold)).foregroundStyle(.white)
                        Text("Unit \(crew.unitNumber.isEmpty ? "—" : crew.unitNumber)").font(.caption2).foregroundStyle(color)
                    }.padding(.trailing, 4)
                }
            }.padding(6).background(HaloTheme.fieldChrome, in: Capsule())
                .overlay { Capsule().stroke(color.opacity(0.8), lineWidth: selected ? 2 : 1) }
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 10)).foregroundStyle(color).offset(y: -1)
        }
    }
}
