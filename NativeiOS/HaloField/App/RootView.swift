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

    init() {
        UITabBar.appearance().unselectedItemTintColor = UIColor.white.withAlphaComponent(0.45)
        UITabBar.appearance().backgroundColor = UIColor(red: 9/255, green: 23/255, blue: 34/255, alpha: 0.98)
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
        .onReceive(NotificationCenter.default.publisher(for: .haloPendingActionCreated)) { _ in
            fieldSync.refreshPendingCount(context: modelContext, activationToken: session.activationToken)
            guard network.isConnected else { return }
            Task {
                await fieldSync.flush(context: modelContext, activationToken: session.activationToken)
            }
        }
    }

    private var tabShell: some View {
        TabView {
            NavigationStack { TodayView() }
                .tabItem { Label("Today", systemImage: "bolt.fill") }

            NavigationStack { JobsView() }
                .tabItem { Label("Jobs", systemImage: "square.stack.3d.up.fill") }

            NavigationStack { HaloAssistantView() }
                .tabItem { Label("Halo", systemImage: "sparkles") }

            NavigationStack { ProfileView() }
                .tabItem { Label("Me", systemImage: "person.crop.circle") }
        }
        .tint(HaloTheme.lime)
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
    }
}

private struct HaloAssistantView: View {
    @State private var text = ""
    var body: some View {
        VStack(spacing: 18) {
            HaloLogo(height: 30)
            Spacer()
            Image(systemName: "sparkles").font(.system(size: 38, weight: .medium)).foregroundStyle(HaloTheme.lime)
            Text("Ask HALO").font(HaloType.display(30, weight: .semibold)).foregroundStyle(.white)
            Text("Jobs, instructions, property notes, handoffs, or what to do next.")
                .font(HaloType.body(14)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.5))
            Spacer()
            HStack {
                TextField("Ask about your work…", text: $text).foregroundStyle(.white)
                Button { } label: {
                    Image(systemName: "arrow.up").fontWeight(.bold)
                        .frame(width: 40, height: 40)
                        .background(HaloTheme.lime).foregroundStyle(HaloTheme.ink).clipShape(Circle())
                }
            }
            .padding(10).background(Color.white.opacity(0.06)).clipShape(Capsule())
            .overlay(Capsule().stroke(HaloTheme.fieldBorder))
        }
        .padding(HaloTheme.horizontal)
        .background(HaloTheme.fieldBackground.ignoresSafeArea())
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct ProfileView: View {
    @EnvironmentObject private var session: HaloSessionStore
    @EnvironmentObject private var store: JobStore
    @EnvironmentObject private var fieldSync: FieldSyncController
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var notifications: HaloNotificationService

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
                HStack {
                    Label(network.isConnected ? "Field sync" : "Offline mode", systemImage: network.isConnected ? "arrow.triangle.2.circlepath" : "wifi.slash")
                    Spacer()
                    Text(fieldSync.attentionCount > 0
                         ? "\(fieldSync.attentionCount) need attention"
                         : (fieldSync.pendingCount == 0 ? "Up to date" : "\(fieldSync.pendingCount) pending"))
                        .font(.caption)
                        .foregroundStyle(fieldSync.pendingCount == 0 && fieldSync.attentionCount == 0 ? HaloTheme.fieldLive : HaloTheme.warning)
                }
                Label("Location verification", systemImage: "location.fill")

                Button {
                    Task {
                        if notifications.authorizationStatus == .notDetermined {
                            _ = await notifications.requestAuthorization()
                        } else {
                            await notifications.refreshAuthorization()
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
                Label("Crew profile", systemImage: "person.2.fill")
                Label("Settings", systemImage: "gearshape.fill")
                Button(role: .destructive) {
                    store.clear()
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
    }
}