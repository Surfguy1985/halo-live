import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: JobStore
    @EnvironmentObject private var session: HaloSessionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let error = store.syncError {
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
                        .fill(store.syncError == nil ? HaloTheme.fieldLive : HaloTheme.warning)
                        .frame(width: 7, height: 7)
                    Text(store.isRefreshing ? "SYNCING" : "LIVE")
                        .font(HaloType.body(10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("GOOD MORNING")
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
