import SwiftUI
import UIKit

struct ActivationView: View {
    @EnvironmentObject private var session: HaloSessionStore
    @EnvironmentObject private var store: JobStore
    @State private var token = ""
    @State private var error: String?
    @State private var isActivating = false

    var body: some View {
        ZStack {
            HaloTheme.fieldBackground.ignoresSafeArea()
            RadialGradient(
                colors: [HaloTheme.actionBlue.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 420
            )
            .ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(HaloTheme.lime.opacity(0.08))
                        .frame(width: 112, height: 112)
                        .blur(radius: 1)
                    HaloLogo(height: 36)
                }

                VStack(spacing: 9) {
                    Text("Activate HALO Field")
                        .font(HaloType.display(30, weight: .semibold))
                        .tracking(-1)
                        .foregroundStyle(.white)
                    Text("Open your crew activation link on this iPhone, or paste the secure token below.")
                        .font(HaloType.body(13))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                VStack(spacing: 12) {
                    SecureField("Crew activation token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(HaloType.body(14, weight: .medium))
                        .padding(.horizontal, 16)
                        .frame(height: 54)
                        .background(Color.white.opacity(0.06))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(HaloTheme.fieldBorder)
                        }

                    Button {
                        let candidate = token.trimmingCharacters(in: .whitespacesAndNewlines)
                        isActivating = true
                        error = nil

                        Task {
                            do {
                                _ = try await session.activateValidated(token: candidate)
                                await MainActor.run {
                                    isActivating = false
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                }
                            } catch {
                                await MainActor.run {
                                    isActivating = false
                                    self.error = error.localizedDescription
                                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(isActivating ? "Verifying with HALO…" : "Activate this iPhone")
                            Spacer()
                            if isActivating { ProgressView().tint(HaloTheme.ink) }
                            else { Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold)) }
                        }
                    }
                    .buttonStyle(HaloPrimaryButtonStyle())
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isActivating)

                    if let error {
                        Text(error)
                            .font(HaloType.body(11, weight: .medium))
                            .foregroundStyle(Color.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                    }

#if DEBUG
                    Text(HaloAPI.connectionRevision)
                        .font(HaloType.body(9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .accessibilityLabel("Connection build \(HaloAPI.connectionRevision)")

                    HStack {
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                        Text("XCODE PREVIEW")
                            .font(HaloType.body(9, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(.white.opacity(0.32))
                        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                    }
                    .padding(.vertical, 4)

                    Button {
                        store.loadPreview()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "iphone.gen3")
                            Text("Preview HALO Field")
                        }
                        .font(HaloType.body(14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundStyle(.white)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().stroke(Color.white.opacity(0.12))
                        }
                    }
#endif
                }
                .padding(18)
                .haloDarkCard()

                HStack(spacing: 7) {
                    Image(systemName: "lock.shield.fill")
                    Text("Encrypted activation · stored in this iPhone’s Keychain")
                }
                .font(HaloType.body(10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))

                Spacer()
            }
            .padding(.horizontal, 22)
        }
    }
}
