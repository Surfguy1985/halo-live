import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: JobStore
    @EnvironmentObject private var session: HaloSessionStore
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var fieldSync: FieldSyncController
    @EnvironmentObject private var realtime: HaloRealtimeService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let error = store.syncError, network.isConnected {
                    syncErrorCard(error)
                }

                if store.isLoading && store.jobs.isEmpty {
                    loadingState
                } else if store.jobs.isEmpty {
                    emptyState
                } else {
                    if let next = store.nextJob {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("NEXT JOB")
                                .font(HaloType.body(10, weight: .bold))
                                .tracking(1.8)
                                .foregroundStyle(.white.opacity(0.42))

                            NavigationLink { JobDetailView(jobID: next.id) } label: {
                                FieldJobCard(job: next, hero: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    let remainder = store.jobs.filter { $0.id != store.nextJob?.id && !$0.isClosed }
                    if !remainder.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Up next")
                                    .font(HaloType.display(20, weight: .semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("\(store.activeJobCount) active")
                                    .font(HaloType.body(12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.45))
                            }

                            ForEach(remainder) { job in
                                NavigationLink { JobDetailView(jobID: job.id) } label: {
                                    FieldJobCard(job: job, hero: false)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, HaloTheme.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(
            ZStack {
                HaloTheme.fieldBackground
                RadialGradient(
                    colors: [HaloTheme.actionBlue.opacity(0.16), .clear],
                    center: .topTrailing,
                    startRadius: 10,
                    endRadius: 360
                )
            }
            .ignoresSafeArea()
        )
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.loadIfNeeded(activationToken: session.activationToken) }
        .refreshable { await store.refresh(activationToken: session.activationToken) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HaloLogo(height: 27)
                Spacer()
                HStack(spacing: 7) {
                    Circle()
                        .fill(syncIndicatorColor)
                        .frame(width: 7, height: 7)
                    Text(syncIndicatorText)
                        .font(HaloType.body(10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            if !network.isConnected {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                    Text(fieldSync.pendingCount > 0
                         ? "OFFLINE · \(fieldSync.pendingCount) CHANGE\(fieldSync.pendingCount == 1 ? "" : "S") SAVED ON THIS IPHONE"
                         : "OFFLINE MODE · YOUR LAST SYNCED JOBS STAY AVAILABLE")
                }
                .font(HaloType.body(9, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(HaloTheme.warning)
            } else if fieldSync.pendingCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: fieldSync.isSyncing ? "arrow.triangle.2.circlepath" : "icloud.and.arrow.up")
                    Text(fieldSync.isSyncing
                         ? "SYNCING \(fieldSync.pendingCount) SAVED CHANGE\(fieldSync.pendingCount == 1 ? "" : "S")"
                         : "\(fieldSync.pendingCount) SAVED CHANGE\(fieldSync.pendingCount == 1 ? "" : "S") WAITING TO SYNC")
                }
                .font(HaloType.body(9, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(HaloTheme.lime)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(greeting.uppercased())
                    .font(HaloType.body(10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(.white.opacity(0.4))
                Text("Ready to move.")
                    .font(HaloType.display(34, weight: .semibold))
                    .tracking(-1.4)
                    .foregroundStyle(.white)
            }

            HStack(spacing: 10) {
                Label("\(store.activeJobCount) active", systemImage: "briefcase.fill")
                Text("•")
                Label("\(store.attentionCount) need attention", systemImage: "exclamationmark.circle.fill")
            }
            .font(HaloType.body(12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var syncIndicatorText: String {
        if !network.isConnected { return "OFFLINE" }
        if fieldSync.isSyncing || store.isRefreshing { return "SYNCING" }
        if fieldSync.pendingCount > 0 { return "\(fieldSync.pendingCount) TO SYNC" }
        if store.syncError != nil { return "ATTENTION" }
        switch realtime.state {
        case .connected: return "LIVE"
        case .connecting, .reconnecting: return "CONNECTING"
        case .expired: return "ACTIVATE"
        case .stopped: return "CONNECTED"
        }
    }

    private var syncIndicatorColor: Color {
        if !network.isConnected { return HaloTheme.warning }
        if fieldSync.isSyncing || store.isRefreshing { return HaloTheme.actionBlue }
        if fieldSync.pendingCount > 0 { return HaloTheme.lime }
        if store.syncError != nil { return HaloTheme.warning }
        switch realtime.state {
        case .connected: return HaloTheme.fieldLive
        case .connecting, .reconnecting: return HaloTheme.actionBlue
        case .expired: return HaloTheme.warning
        case .stopped: return .white.opacity(0.45)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView().tint(HaloTheme.lime).scaleEffect(1.1)
            Text("Syncing live HALO jobs…")
                .font(HaloType.body(13, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 34))
                .foregroundStyle(HaloTheme.lime)
            Text("No active jobs")
                .font(HaloType.card(20, weight: .semibold))
                .foregroundStyle(.white)
            Text("Pull to refresh when the office assigns new work.")
                .font(HaloType.body(12))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }

    private func syncErrorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(HaloTheme.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text("Live sync needs attention")
                    .font(HaloType.body(13, weight: .bold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(HaloType.body(11))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Button("Retry") {
                Task { await store.refresh(activationToken: session.activationToken) }
            }
            .font(HaloType.body(11, weight: .bold))
            .foregroundStyle(HaloTheme.lime)
        }
        .padding(16)
        .haloDarkCard()
    }
}
