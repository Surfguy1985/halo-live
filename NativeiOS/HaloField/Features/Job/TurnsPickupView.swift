import SwiftUI
import UIKit

struct TurnsPickupView: View {
    @EnvironmentObject private var session: HaloSessionStore
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var store: JobStore

    @State private var handoffs: [TurnHandoff] = []
    @State private var selected: TurnHandoff?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if !handoffs.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TURNS PICKUP")
                                .font(HaloType.body(9, weight: .bold))
                                .tracking(1.6)
                                .foregroundStyle(HaloTheme.lime)
                            Text("\(handoffs.count) handoff\(handoffs.count == 1 ? "" : "s") ready")
                                .font(HaloType.card(19, weight: .semibold))
                                .foregroundStyle(.white)
                        }

                        Spacer()

                        Button {
                            Task { await refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 38, height: 38)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Circle())
                        }
                        .foregroundStyle(.white.opacity(0.68))
                        .disabled(isLoading || !network.isConnected)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(handoffs) { handoff in
                                Button {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    selected = handoff
                                } label: {
                                    pickupCard(handoff)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .sheet(item: $selected) { handoff in
                    HandoffPickupDetailView(
                        handoff: handoff,
                        onClaimed: {
                            handoffs.removeAll { $0.id == handoff.id }
                            Task {
                                await store.refresh(activationToken: session.activationToken)
                            }
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            } else if let errorMessage, network.isConnected {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(errorMessage)
                    Spacer()
                    Button("Retry") { Task { await refresh() } }
                }
                .font(HaloType.body(10, weight: .semibold))
                .foregroundStyle(HaloTheme.warning)
                .padding(14)
                .haloDarkCard()
            }
        }
        .task(id: session.activationToken) {
            await refresh()
        }
    }

    private func pickupCard(_ handoff: TurnHandoff) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("HANDOFF")
                    .font(HaloType.body(8, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(HaloTheme.ink)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(HaloTheme.lime)
                    .clipShape(Capsule())

                Spacer()

                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(HaloTheme.lime)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Unit \(handoff.unit)")
                    .font(HaloType.card(20, weight: .bold))
                    .foregroundStyle(.white)
                Text(handoff.propertyName)
                    .font(HaloType.body(12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(1)
            }

            Text(handoff.summary)
                .font(HaloType.body(12, weight: .medium))
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(2)
                .frame(minHeight: 34, alignment: .topLeading)

            HStack {
                Label("Ready to pick up", systemImage: "person.crop.circle.badge.plus")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(HaloType.body(10, weight: .bold))
            .foregroundStyle(HaloTheme.lime)
        }
        .padding(16)
        .frame(width: 252, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    HaloTheme.fieldCard,
                    HaloTheme.fieldChrome.opacity(0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(HaloTheme.fieldBorder, lineWidth: 1)
        }
    }

    private func refresh() async {
        guard
            network.isConnected,
            let token = session.activationToken,
            !token.isEmpty
        else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            handoffs = try await HaloAPI.shared.fetchOpenTurnHandoffs(
                activationToken: token
            )
            errorMessage = nil
        } catch {
            errorMessage = "Turn pickups could not refresh."
        }
    }
}

private struct HandoffPickupDetailView: View {
    let handoff: TurnHandoff
    let onClaimed: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: HaloSessionStore
    @EnvironmentObject private var network: NetworkMonitor

    @State private var isClaiming = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("TURN HANDOFF")
                        .font(HaloType.body(9, weight: .bold))
                        .tracking(1.6)
                        .foregroundStyle(HaloTheme.lime)
                    Text("Unit \(handoff.unit)")
                        .font(HaloType.display(34, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(handoff.propertyName)
                        .font(HaloType.card(16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(handoff.address)
                        .font(HaloType.body(11))
                        .foregroundStyle(.white.opacity(0.42))
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("WORK REQUESTED")
                        .font(HaloType.body(9, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.36))
                    Text(handoff.summary)
                        .font(HaloType.body(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(17)
                .frame(maxWidth: .infinity, alignment: .leading)
                .haloDarkCard()

                HStack(spacing: 10) {
                    statusChip(icon: "building.2.fill", text: "Same property")
                    statusChip(icon: "link", text: "Source linked")
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(HaloType.body(11, weight: .semibold))
                        .foregroundStyle(HaloTheme.warning)
                }

                Spacer()

                Button {
                    claim()
                } label: {
                    HStack {
                        Text(isClaiming ? "Picking Up…" : "Pick Up Handoff")
                        Spacer()
                        if isClaiming {
                            ProgressView().tint(HaloTheme.ink)
                        } else {
                            Image(systemName: "checkmark")
                        }
                    }
                    .font(HaloType.body(15, weight: .bold))
                    .padding(.horizontal, 22)
                    .frame(height: 58)
                    .background(network.isConnected ? HaloTheme.lime : Color.white.opacity(0.08))
                    .foregroundStyle(network.isConnected ? HaloTheme.ink : .white.opacity(0.3))
                    .clipShape(Capsule())
                }
                .disabled(isClaiming || !network.isConnected)

                if !network.isConnected {
                    Text("Reconnect to claim. Pickup is atomic so two crews can’t take the same handoff.")
                        .font(HaloType.body(9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.38))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
            .background(HaloTheme.fieldBackground.ignoresSafeArea())
            .navigationTitle("Pickup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func statusChip(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(HaloType.body(10, weight: .bold))
            .foregroundStyle(.white.opacity(0.58))
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(Color.white.opacity(0.055))
            .clipShape(Capsule())
    }

    private func claim() {
        guard
            let token = session.activationToken,
            !token.isEmpty,
            network.isConnected
        else { return }

        isClaiming = true
        errorMessage = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            do {
                try await HaloAPI.shared.claimTurnHandoff(
                    id: handoff.id,
                    activationToken: token
                )
                await MainActor.run {
                    isClaiming = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onClaimed()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isClaiming = false
                    errorMessage = error.localizedDescription
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
}
