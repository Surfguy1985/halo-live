import SwiftUI

/// Native rendering of Figma screen 77 (Apply) and 78 (Accepted).
/// Neither state implies that the preview job is published or assigned.
struct HaloMarketplaceApplicationPreviewView: View {
    enum Mode { case apply, assigned }
    let mode: Mode
    let job: HaloMarketplaceOpportunity
    @Environment(\.dismiss) private var dismiss

    private var title: String { mode == .apply ? "Apply" : "Accepted" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button("Explore", systemImage: "chevron.left") { dismiss() }
                        .font(HaloMarketplaceDesign.font(14, weight: .semibold))
                    Spacer()
                    HaloMarketplaceWing()
                }
                .padding(.top, 14)

                Text(title)
                    .font(HaloMarketplaceDesign.font(28, weight: .bold))
                    .foregroundStyle(HaloMarketplaceDesign.ink)
                    .padding(.top, 5)
                Text("DALLAS–FORT WORTH  ·  DESIGN PREVIEW")
                    .font(HaloMarketplaceDesign.font(11))
                    .tracking(0.55)
                    .foregroundStyle(HaloMarketplaceDesign.slate)

                VStack(alignment: .leading, spacing: 12) {
                    Text("ILLUSTRATIVE OPPORTUNITY")
                        .font(HaloMarketplaceDesign.font(11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(HaloMarketplaceDesign.midnight, in: Capsule())
                    Text(job.title)
                        .font(HaloMarketplaceDesign.font(21, weight: .bold))
                        .foregroundStyle(HaloMarketplaceDesign.ink)
                    Text(job.locality)
                        .font(HaloMarketplaceDesign.font(13))
                        .foregroundStyle(HaloMarketplaceDesign.slate)
                    Text(job.payout)
                        .font(HaloMarketplaceDesign.font(24, weight: .bold))
                        .foregroundStyle(HaloMarketplaceDesign.earningGreen)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(.white, in: RoundedRectangle(cornerRadius: 22))

                detail("Job scope", job.scope.joined(separator: " · "))
                detail("Scheduled", job.scheduledStart.formatted(date: .abbreviated, time: .shortened))
                detail("Requirements", "Requirements not verified for design-preview opportunities")
                detail("Payment", "No payment is secured or committed for this preview")

                Label(
                    mode == .apply
                        ? "Applications require an authorized marketplace account and an active listing. This demo cannot submit requests."
                        : "This is the Figma accepted-state design, not an assignment. No job was accepted and no work is authorized.",
                    systemImage: "info.circle"
                )
                .font(HaloMarketplaceDesign.font(12))
                .foregroundStyle(HaloMarketplaceDesign.slate)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)

                HaloMarketplacePrimaryButton(
                    title: mode == .apply ? "Submit application · unavailable" : "Open assigned job · unavailable",
                    enabled: false,
                    action: {}
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 35)
        }
        .background(HaloMarketplaceDesign.pearl.ignoresSafeArea())
        .tint(HaloMarketplaceDesign.steelBlue)
        .preferredColorScheme(.light)
    }

    private func detail(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(HaloMarketplaceDesign.font(11, weight: .semibold))
                .foregroundStyle(HaloMarketplaceDesign.slate)
            Text(text)
                .font(HaloMarketplaceDesign.font(13))
                .foregroundStyle(HaloMarketplaceDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 65, alignment: .leading)
        .padding(.horizontal, 16)
        .background(.white, in: RoundedRectangle(cornerRadius: 15))
    }
}

/// Figma 80: contractor availability preferences. The local preview state
/// never changes real marketplace eligibility, profile or worker dispatch.
struct HaloMarketplaceAvailabilityPreviewView: View {
    @State private var previewAvailable = false
    @State private var preferredIndustries: Set<HaloMarketplaceIndustry> = [
        .construction, .property
    ]
    @State private var radiusMiles = 25.0
    @State private var savedInPreview = false

    private let availableIndustries: [HaloMarketplaceIndustry] = [
        .construction, .property, .cleaning, .transportation, .security, .hospitality
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                HStack {
                    Text("Contractor · Available For Work")
                        .font(HaloMarketplaceDesign.font(25, weight: .bold))
                        .foregroundStyle(HaloMarketplaceDesign.ink)
                        .minimumScaleFactor(0.75)
                    Spacer()
                    HaloMarketplaceWing()
                }
                .padding(.top, 14)

                Text("DALLAS–FORT WORTH  ·  DESIGN PREVIEW")
                    .font(HaloMarketplaceDesign.font(11))
                    .tracking(0.55)
                    .foregroundStyle(HaloMarketplaceDesign.slate)

                HStack(spacing: 15) {
                    Image(systemName: "bolt.shield.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(HaloMarketplaceDesign.earningGreen)
                        .frame(width: 54, height: 54)
                        .background(HaloMarketplaceDesign.mapCanvas, in: RoundedRectangle(cornerRadius: 17))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(previewAvailable ? "Preview: You're available" : "Preview: You're unavailable")
                            .font(HaloMarketplaceDesign.font(18, weight: .bold))
                            .foregroundStyle(HaloMarketplaceDesign.ink)
                        Text("Availability is not synced with any dispatch or staffing service.")
                            .font(HaloMarketplaceDesign.font(12))
                            .foregroundStyle(HaloMarketplaceDesign.slate)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Toggle("Preview availability", isOn: $previewAvailable)
                        .labelsHidden()
                        .tint(HaloMarketplaceDesign.earningGreen)
                }
                .padding(18)
                .background(.white, in: RoundedRectangle(cornerRadius: 21))

                VStack(alignment: .leading, spacing: 13) {
                    Text("Preferred industries")
                        .font(HaloMarketplaceDesign.font(16, weight: .bold))
                        .foregroundStyle(HaloMarketplaceDesign.ink)
                    ForEach(availableIndustries) { industry in
                        Button {
                            if preferredIndustries.contains(industry) {
                                preferredIndustries.remove(industry)
                            } else {
                                preferredIndustries.insert(industry)
                            }
                        } label: {
                            HStack {
                                Text(industry.rawValue)
                                    .font(HaloMarketplaceDesign.font(14, weight: .medium))
                                Spacer()
                                Image(systemName: preferredIndustries.contains(industry)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(HaloMarketplaceDesign.steelBlue)
                            }
                            .frame(minHeight: 43)
                            .foregroundStyle(HaloMarketplaceDesign.ink)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(preferredIndustries.contains(industry) ? .isSelected : [])
                        if industry != availableIndustries.last {
                            Divider().overlay(HaloMarketplaceDesign.border)
                        }
                    }
                }
                .padding(17)
                .background(.white, in: RoundedRectangle(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Preferred work radius")
                            .font(HaloMarketplaceDesign.font(16, weight: .semibold))
                            .foregroundStyle(HaloMarketplaceDesign.ink)
                        Spacer()
                        Text("\(Int(radiusMiles)) miles")
                            .font(HaloMarketplaceDesign.font(14, weight: .semibold))
                            .foregroundStyle(HaloMarketplaceDesign.steelBlue)
                    }
                    Slider(value: $radiusMiles, in: 5...100, step: 5)
                        .tint(HaloMarketplaceDesign.steelBlue)
                        .accessibilityLabel("Preferred work radius")
                }
                .padding(18)
                .background(.white, in: RoundedRectangle(cornerRadius: 20))

                HaloMarketplacePrimaryButton(
                    title: savedInPreview ? "Preview preferences saved" : "Save preview preferences"
                ) {
                    // Confirm only local SwiftUI preview state, never a server mutation.
                    savedInPreview = true
                }
                Text(savedInPreview
                     ? "Saved in this preview only. Your real worker availability and credentials were not changed."
                     : "Preferences are temporary design-preview state. Your real profile is unchanged.")
                    .font(HaloMarketplaceDesign.font(12))
                    .foregroundStyle(HaloMarketplaceDesign.slate)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(HaloMarketplaceDesign.pearl.ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}

#if DEBUG
#Preview("HALO · Figma 80 · Availability") {
    HaloMarketplaceAvailabilityPreviewView()
}
#endif
