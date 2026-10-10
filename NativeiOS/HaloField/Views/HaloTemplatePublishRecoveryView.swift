import SwiftUI

/// A deliberate recovery surface for an uncertain publish. The action label is
/// intentionally phrased as an outcome check so it is never mistaken for a new
/// publish request.
struct HaloTemplatePublishRecoveryView: View {
    @ObservedObject var recovery: HaloTemplatePublishRecovery

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Expected current revision \(proposal.expectedRevision)")
                Text("Recovery ID \(proposal.requestID.uuidString.suffix(8))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            if case .reconciling = recovery.state {
                HStack(spacing: 9) {
                    ProgressView()
                    Text("Checking the original request…")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityElement(children: .combine)
            } else if recovery.canCheckOutcome {
                Button {
                    Task { await recovery.checkPublishOutcome() }
                } label: {
                    Label("Check publish outcome", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Checks using the original request ID and expected revision. It does not create a new publish request.")
            }
        }
        .padding(16)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.orange.opacity(0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var proposal: HaloTemplatePublishing.Proposal {
        recovery.uncertainPublish.originalProposal
    }

    private var title: String {
        switch recovery.state {
        case .awaitingUserAction, .retryAvailable:
            return "Publish status unknown"
        case .reconciling:
            return "Checking publish status"
        case .published:
            return "Publish confirmed"
        case .needsAttention(.authenticationRequired):
            return "Sign in to continue"
        case .needsAttention:
            return "Publish needs review"
        }
    }

    private var message: String {
        switch recovery.state {
        case .awaitingUserAction:
            return "The server may have saved this change. Check its outcome before making another publish request."
        case .reconciling:
            return "HALO is checking the original request without changing its revision or recovery ID."
        case let .published(receipt):
            return "The server confirmed template version \(receipt.templateVersion) at revision \(receipt.revision)."
        case .retryAvailable(.outcomeStillUnknown):
            return "The server still could not confirm the result. You can check again with the same recovery ID."
        case .retryAvailable(.serviceUnavailable):
            return "The publishing service is unavailable. No new request was created; check again when it returns."
        case .retryAvailable(.connectionLost):
            return "The connection ended before HALO could verify the result. Check again with the same recovery ID."
        case .retryAvailable(.invalidReceipt):
            return "HALO received a response it could not verify. Check again or contact support if this continues."
        case .retryAvailable(.publishRequestNotFound):
            return "No durable receipt was found yet. Do not publish again; check the same recovery ID or contact support."
        case .retryAvailable(.interrupted):
            return "The check was interrupted. The original request is still preserved."
        case .needsAttention(.authenticationRequired):
            return "Your session is missing or expired. Sign in, then check the original request again."
        case .needsAttention(.accessRevoked):
            return "Your account no longer has permission to verify this publish. Contact an administrator."
        case .needsAttention(.revisionConflict):
            return "The workflow revision changed before the original request could be verified. Do not publish again until an administrator reviews it."
        case .needsAttention(.idempotencyConflict):
            return "The recovery ID does not match the server record. Stop and contact support."
        case .needsAttention(.invalidProposal):
            return "The server rejected the preserved proposal. Review the workflow before taking further action."
        case .needsAttention(.invalidConfiguration):
            return "HALO cannot reach a trusted staging publishing service. Contact support."
        }
    }

    private var iconName: String {
        switch recovery.state {
        case .published: return "checkmark.seal.fill"
        case .needsAttention: return "exclamationmark.triangle.fill"
        default: return "questionmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch recovery.state {
        case .published: return .green
        case .needsAttention: return .red
        default: return .orange
        }
    }
}
