import SwiftUI

/// Figma screen 76 translated into native SwiftUI. No backend payment,
/// assignment, or customer-verification claim is inferred from preview data.
struct HaloMarketplaceDetailView: View {
    let job: HaloMarketplaceOpportunity
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Label("Explore", systemImage: "chevron.left")
                            .font(HaloMarketplaceDesign.font(14, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    HaloMarketplaceWing()
                }
                .padding(.top, 13)

                Text("Detail")
                    .font(HaloMarketplaceDesign.font(28, weight: .bold))
                    .foregroundStyle(HaloMarketplaceDesign.ink)
                    .padding(.top, 6)

                Text(job.previewOnly ? "ILLUSTRATIVE JOB · DESIGN PREVIEW" : job.locality)
                    .font(HaloMarketplaceDesign.font(11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(HaloMarketplaceDesign.slate)

                VStack(alignment: .leading, spacing: 15) {
                    Text(job.customerVerified && !job.previewOnly
                         ? "Verified customer" : "Customer verification not established")
                        .font(HaloMarketplaceDesign.font(11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .background(HaloMarketplaceDesign.midnight, in: Capsule())

                    Text(job.title)
                        .font(HaloMarketplaceDesign.font(22, weight: .bold))
                        .foregroundStyle(HaloMarketplaceDesign.ink)

                    Label(job.locality, systemImage: "mappin")
                        .font(HaloMarketplaceDesign.font(13))
                        .foregroundStyle(HaloMarketplaceDesign.slate)

                    Text(job.payout)
                        .font(HaloMarketplaceDesign.font(28, weight: .bold))
                        .foregroundStyle(HaloMarketplaceDesign.earningGreen)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(19)
                .background(.white, in: RoundedRectangle(cornerRadius: 22))

                infoRow(
                    heading: "Job scope",
                    value: job.scope.joined(separator: " · "),
                    icon: "checklist"
                )
                infoRow(
                    heading: "Scheduled",
                    value: job.scheduledStart.formatted(date: .abbreviated, time: .shortened),
                    icon: "calendar"
                )
                infoRow(
                    heading: "Estimated duration",
                    value: "\(job.durationMinutes) minutes",
                    icon: "clock"
                )
                infoRow(
                    heading: "Requirements",
                    value: job.previewOnly
                        ? "Illustrative only · eligibility not evaluated"
                        : "Eligibility must be verified by HALO before an assignment",
                    icon: "checkmark.shield"
                )
                infoRow(
                    heading: "Payment",
                    value: job.previewOnly
                        ? "Demonstration amount · no payment commitment"
                        : "Payment terms require an authoritative backend response",
                    icon: "creditcard"
                )

                if job.previewOnly {
                    Label(
                        "This is a design preview, not a published job. Do not travel or begin work.",
                        systemImage: "info.circle"
                    )
                    .font(HaloMarketplaceDesign.font(12))
                    .foregroundStyle(HaloMarketplaceDesign.slate)
                    .padding(.horizontal, 2)
                    .padding(.top, 5)
                }

                HaloMarketplacePrimaryButton(
                    title: "Request unavailable in design preview",
                    enabled: false,
                    action: {}
                )
                .padding(.top, 7)

                Text("Requesting a job is never the same as being assigned to it.")
                    .font(HaloMarketplaceDesign.font(11))
                    .foregroundStyle(HaloMarketplaceDesign.slate)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 35)
        }
        .background(HaloMarketplaceDesign.pearl.ignoresSafeArea())
        .tint(HaloMarketplaceDesign.steelBlue)
        .preferredColorScheme(.light)
    }

    private func infoRow(heading: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(HaloMarketplaceDesign.steelBlue)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 7) {
                Text(heading)
                    .font(HaloMarketplaceDesign.font(11, weight: .semibold))
                    .foregroundStyle(HaloMarketplaceDesign.slate)
                Text(value)
                    .font(HaloMarketplaceDesign.font(13))
                    .foregroundStyle(HaloMarketplaceDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 15))
    }
}

#if DEBUG
#Preview("HALO · Figma 76 · Opportunity Detail") {
    HaloMarketplaceDetailView(job: HaloMarketplacePreview.opportunities[0])
}
#endif
