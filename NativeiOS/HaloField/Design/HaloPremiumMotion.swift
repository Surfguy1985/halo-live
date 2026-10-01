import SwiftUI

struct HaloPulseRing: View {
    var tint: Color = HaloTheme.lime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Circle()
            .stroke(tint.opacity(pulse ? 0.02 : 0.42), lineWidth: 1.5)
            .scaleEffect(reduceMotion ? 1 : (pulse ? 1.55 : 0.82))
            .opacity(reduceMotion ? 0.30 : (pulse ? 0 : 1))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulse = true }
            }
    }
}

struct HaloVectorMark: View {
    enum Kind { case connected, verified, complete, offline }
    let kind: Kind
    var size: CGFloat = 96
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal = false

    private var icon: String {
        switch kind {
        case .connected: "point.3.connected.trianglepath.dotted"
        case .verified: "location.fill.viewfinder"
        case .complete: "checkmark"
        case .offline: "icloud.and.arrow.up"
        }
    }

    private var tint: Color {
        switch kind {
        case .offline: HaloTheme.actionBlue
        default: HaloTheme.lime
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.06)).frame(width: size, height: size)
            HaloPulseRing(tint: tint).frame(width: size * 0.72, height: size * 0.72)
            Circle().stroke(tint.opacity(0.18), lineWidth: 1).frame(width: size * 0.62, height: size * 0.62)
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: size * 0.28, weight: .semibold))
                .foregroundStyle(tint)
                .scaleEffect(reveal ? 1 : 0.72)
                .opacity(reveal ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.68)) { reveal = true }
        }
    }
}

struct HaloMilestoneOverlay: View {
    let title: String
    let subtitle: String
    var kind: HaloVectorMark.Kind = .complete
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 16) {
            HaloVectorMark(kind: kind, size: 118)
            VStack(spacing: 6) {
                Text(title).font(HaloType.display(28, weight: .bold)).foregroundStyle(.white)
                Text(subtitle).font(HaloType.body(12, weight: .medium)).foregroundStyle(.white.opacity(0.50)).multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .background(HaloTheme.fieldCard.opacity(0.78), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 32, style: .continuous).stroke(Color.white.opacity(0.10)) }
        .shadow(color: .black.opacity(0.28), radius: 36, y: 18)
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.78)) { appeared = true } }
    }
}

struct HaloExpandablePanel<Content: View>: View {
    let title: String
    let icon: String
    var badge: String? = nil
    @Binding var expanded: Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(HaloMotion.animation(reduceMotion: reduceMotion)) { expanded.toggle() }
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HaloTheme.actionBlue.opacity(0.11)).frame(width: 40, height: 40)
                        Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(HaloTheme.actionBlue)
                    }
                    Text(title).font(HaloType.body(13, weight: .bold)).foregroundStyle(.white)
                    Spacer()
                    if let badge { HaloStatusPill(text: badge, tint: HaloTheme.lime) }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.34))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(14)
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")

            if expanded {
                Divider().overlay(HaloTheme.hairline)
                content()
                    .padding(14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .haloDarkCard()
    }
}
