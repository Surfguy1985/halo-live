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
                            Text("Next")
                                .font(HaloType.body(15, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.58))

                            NavigationLink { JobDetailView(jobID: next.id) } label: {
                                FieldJobCard(job: next, hero: true)
                            }
                            .buttonStyle(HaloPressableStyle())
                        }
                    }

                    let remainder = store.jobs.filter { $0.id != store.nextJob?.id && !$0.isClosed }
                    if !remainder.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Later")
                                    .font(HaloType.display(20, weight: .semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                            }

                            ForEach(remainder) { job in
                                NavigationLink { JobDetailView(jobID: job.id) } label: {
                                    FieldJobCard(job: job, hero: false)
                                }
                                .buttonStyle(HaloPressableStyle())
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                HaloLogo(height: 25)
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(syncIndicatorColor)
                        .frame(width: 7, height: 7)
                    Text(syncIndicatorText)
                        .font(HaloType.body(10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color.white.opacity(0.06), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(greeting)
                    .font(HaloType.body(14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.50))
                Text("Today")
                    .font(HaloType.display(38, weight: .semibold))
                    .tracking(-1.5)
                    .foregroundStyle(.white)
            }

            if !network.isConnected || fieldSync.pendingCount > 0 {
                HStack(spacing: 10) {
                    Image(systemName: network.isConnected ? "icloud.and.arrow.up" : "wifi.slash")
                        .font(.system(size: 13, weight: .semibold))
                    Text(syncNotice)
                        .font(HaloType.body(11, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(network.isConnected ? HaloTheme.lime : HaloTheme.warning)
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }

            HStack(spacing: 8) {
                summaryPill(value: store.activeJobCount, label: "Active", icon: "briefcase.fill")
                if store.attentionCount > 0 {
                    summaryPill(value: store.attentionCount, label: "Attention", icon: "exclamationmark.circle.fill", emphasized: true)
                }
            }
        }
    }

    private var syncNotice: String {
        if !network.isConnected {
            return fieldSync.pendingCount > 0
                ? "\(fieldSync.pendingCount) saved change\(fieldSync.pendingCount == 1 ? "" : "s") will sync when you reconnect."
                : "Offline. Your last synced jobs are still available."
        }
        if fieldSync.isSyncing {
            return "Syncing saved field work…"
        }
        return "\(fieldSync.pendingCount) saved change\(fieldSync.pendingCount == 1 ? "" : "s") waiting to sync."
    }

    private func summaryPill(value: Int, label: String, icon: String, emphasized: Bool = false) -> some View {
        Label {
            Text("\(value) \(label)")
        } icon: {
            Image(systemName: icon)
        }
        .font(HaloType.body(11, weight: .semibold))
        .foregroundStyle(emphasized ? HaloTheme.warning : .white.opacity(0.62))
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(Color.white.opacity(0.055), in: Capsule())
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
            Text("You're clear")
                .font(HaloType.card(21, weight: .semibold))
                .foregroundStyle(.white)
            Text("New work will appear here automatically.")
                .font(HaloType.body(13))
                .foregroundStyle(.white.opacity(0.48))
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
