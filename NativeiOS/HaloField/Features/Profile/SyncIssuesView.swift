import SwiftData
import SwiftUI

struct SyncIssuesView: View {
    @EnvironmentObject private var session: HaloSessionStore
    @EnvironmentObject private var fieldSync: FieldSyncController
    @EnvironmentObject private var network: NetworkMonitor
    @Environment(\.modelContext) private var modelContext
    @State private var actions: [PendingFieldAction] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if actions.isEmpty {
                    emptyState
                } else {
                    HaloSectionLabel(title: "Saved field work", trailing: "\(actions.count) actions")
                    LazyVStack(spacing: 12) {
                        ForEach(actions, id: \.id) { action in issueCard(action) }
                    }
                    Text("HALO preserves these actions on this iPhone. Retrying replays the original receipt, so recovery does not create a second field action.")
                        .font(HaloType.body(10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.34))
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, HaloTheme.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 34)
        }
        .background(HaloTheme.fieldBackground.ignoresSafeArea())
        .navigationTitle("Sync Issues")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .haloPendingActionCreated)) { _ in refresh() }
        .refreshable {
            if network.isConnected { await fieldSync.flush(context: modelContext, activationToken: session.activationToken) }
            refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill((fieldSync.attentionCount > 0 ? HaloTheme.warning : HaloTheme.fieldLive).opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: fieldSync.attentionCount > 0 ? "exclamationmark.arrow.triangle.2.circlepath" : "checkmark.icloud.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(fieldSync.attentionCount > 0 ? HaloTheme.warning : HaloTheme.fieldLive)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(fieldSync.attentionCount > 0 ? "Recovery needed" : (actions.isEmpty ? "Everything is synced" : "Saved safely"))
                    .font(HaloType.display(22, weight: .semibold))
                    .foregroundStyle(.white)
                Text(network.isConnected ? "HALO will keep retrying saved field work." : "Offline. Your field work is protected on this iPhone.")
                    .font(HaloType.body(11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.46))
            }
            Spacer()
        }
        .padding(16)
        .haloDarkCard()
    }

    private var emptyState: some View {
        VStack(spacing: 13) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(HaloTheme.fieldLive)
            Text("Nothing waiting")
                .font(HaloType.card(19, weight: .semibold))
                .foregroundStyle(.white)
            Text("Every saved field action has reached HALO.")
                .font(HaloType.body(12))
                .foregroundStyle(.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .haloDarkCard()
    }

    private func issueCard(_ action: PendingFieldAction) -> some View {
        let attention = action.requiresAttention == true
        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill((attention ? HaloTheme.warning : HaloTheme.actionBlue).opacity(0.12)).frame(width: 42, height: 42)
                    Image(systemName: icon(for: action.kind))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(attention ? HaloTheme.warning : HaloTheme.actionBlue)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title(for: action.kind)).font(HaloType.body(14, weight: .bold)).foregroundStyle(.white)
                    Text(action.jobID.isEmpty ? "HALO field action" : "Job \(action.jobID)")
                        .font(HaloType.body(10, weight: .medium)).foregroundStyle(.white.opacity(0.36)).lineLimit(1)
                }
                Spacer()
                HaloStatusPill(text: attention ? "Needs attention" : "Pending", tint: attention ? HaloTheme.warning : HaloTheme.fieldLive)
            }

            if let error = action.lastError, !error.isEmpty {
                Text(error)
                    .font(HaloType.body(11, weight: .medium))
                    .foregroundStyle(attention ? HaloTheme.warning : .white.opacity(0.48))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(HaloTheme.hairline)

            HStack {
                Text(action.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(HaloType.body(9, weight: .medium)).foregroundStyle(.white.opacity(0.30))
                if action.retryCount > 0 {
                    Text("· \(action.retryCount) retries").font(HaloType.body(9, weight: .medium)).foregroundStyle(.white.opacity(0.30))
                }
                Spacer()
                if attention {
                    Button("Retry") {
                        OfflineQueue.shared.retryAttention(action, context: modelContext)
                        refresh()
                        if network.isConnected {
                            Task {
                                await fieldSync.flush(context: modelContext, activationToken: session.activationToken)
                                refresh()
                            }
                        }
                    }
                    .font(HaloType.body(11, weight: .bold))
                    .foregroundStyle(HaloTheme.ink)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 40)
                    .background(HaloTheme.lime, in: Capsule())
                    .buttonStyle(HaloPressableStyle())
                }
            }
        }
        .padding(16)
        .haloDarkCard()
    }

    private func refresh() {
        actions = OfflineQueue.shared.scopedActions(in: modelContext, activationToken: session.activationToken)
    }

    private func title(for kind: String) -> String {
        switch PendingActionKind(rawValue: kind) {
        case .workflowState: "Workflow update"
        case .taskToggle: "Checklist update"
        case .proofCaptured: "Photo proof"
        case .turnHandoff: "Turn handoff"
        case .reworkToggle: "Rework update"
        case .messageSend: "Message"
        case .clockPunch: "Verified work punch"
        case .arrivalCheckIn: "Arrival check-in"
        case nil: "Saved action"
        }
    }

    private func icon(for kind: String) -> String {
        switch PendingActionKind(rawValue: kind) {
        case .workflowState: "arrow.triangle.2.circlepath"
        case .taskToggle: "checklist"
        case .proofCaptured: "camera.fill"
        case .turnHandoff: "arrow.right.square.fill"
        case .reworkToggle: "arrow.counterclockwise.circle.fill"
        case .messageSend: "message.fill"
        case .clockPunch: "clock.badge.checkmark.fill"
        case .arrivalCheckIn: "camera.badge.ellipsis"
        case nil: "exclamationmark.circle"
        }
    }
}
