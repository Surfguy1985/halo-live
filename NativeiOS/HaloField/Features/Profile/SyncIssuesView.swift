import SwiftData
import SwiftUI

struct SyncIssuesView: View {
    @EnvironmentObject private var session: HaloSessionStore
    @EnvironmentObject private var fieldSync: FieldSyncController
    @EnvironmentObject private var network: NetworkMonitor
    @Environment(\.modelContext) private var modelContext

    @State private var actions: [PendingFieldAction] = []

    var body: some View {
        List {
            if actions.isEmpty {
                ContentUnavailableView(
                    "Everything is synced",
                    systemImage: "checkmark.circle.fill",
                    description: Text("HALO has no saved field actions waiting for recovery.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(actions, id: \.id) { action in
                        issueRow(action)
                    }
                } header: {
                    Text("Saved field work")
                } footer: {
                    Text("HALO preserves these actions on this iPhone. Retrying does not create a second action; the original receipt is replayed.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(HaloTheme.fieldBackground)
        .navigationTitle("Sync Issues")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .haloPendingActionCreated)) { _ in
            refresh()
        }
        .refreshable {
            if network.isConnected {
                await fieldSync.flush(context: modelContext, activationToken: session.activationToken)
            }
            refresh()
        }
    }

    private func issueRow(_ action: PendingFieldAction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title(for: action.kind), systemImage: icon(for: action.kind))
                    .font(.headline)
                Spacer()
                statusPill(action)
            }

            Text("Job \(action.jobID)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let error = action.lastError, !error.isEmpty {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(action.requiresAttention == true ? HaloTheme.warning : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text(action.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if action.retryCount > 0 {
                    Text("· \(action.retryCount) retries")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if action.requiresAttention == true {
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
                    .buttonStyle(.borderedProminent)
                    .tint(HaloTheme.lime)
                    .foregroundStyle(HaloTheme.ink)
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func statusPill(_ action: PendingFieldAction) -> some View {
        let attention = action.requiresAttention == true
        Text(attention ? "NEEDS ATTENTION" : "PENDING")
            .font(.caption2.bold())
            .foregroundStyle(attention ? HaloTheme.warning : HaloTheme.fieldLive)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background((attention ? HaloTheme.warning : HaloTheme.fieldLive).opacity(0.12))
            .clipShape(Capsule())
    }

    private func refresh() {
        actions = OfflineQueue.shared.scopedActions(
            in: modelContext,
            activationToken: session.activationToken
        )
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
        case nil: "exclamationmark.circle"
        }
    }
}
