import SwiftUI

/// Source-of-truth preview index for the complete 84-screen HALO Figma system.
///
/// Screen IDs 1–72 are DESIGN SPECS still pending individual SwiftUI ports.
/// IDs 73–84 have an interactive native preview destination. Never mistake
/// this development navigator for a complete backend or App Store feature.
struct HaloFigmaScreenLibraryView: View {
    @State private var search = ""
    @State private var selectedArea: HaloFigmaArea?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rows: [HaloFigmaScreen] {
        HaloFigmaScreenCatalog.screens.filter { screen in
            (selectedArea == nil || screen.area == selectedArea) &&
            (search.isEmpty || screen.name.localizedStandardContains(search) ||
             String(screen.number).contains(search))
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 13) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("HALO DESIGN SYSTEM")
                            .font(HaloMarketplaceDesign.font(11, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(HaloMarketplaceDesign.steelBlue)
                        Text("84-screen library")
                            .font(HaloMarketplaceDesign.font(27, weight: .bold))
                            .foregroundStyle(HaloMarketplaceDesign.ink)
                    }
                    Spacer()
                    HaloMarketplaceWing()
                }
                .padding(.top, 14)
                Text("Official HALO Figma file · iPhone 393 × 852. Preview routes are not production-ready.")
                    .font(HaloMarketplaceDesign.font(13))
                    .foregroundStyle(HaloMarketplaceDesign.slate)
                HStack(spacing: 12) {
                    countCard("\(HaloFigmaScreenCatalog.screens.count)", "Mapped")
                    countCard("\(HaloFigmaScreenCatalog.screens.filter(\.nativePreviewAvailable).count)", "Native preview routes")
                }

                TextField("Find a screen or number", text: $search)
                    .font(HaloMarketplaceDesign.font(14))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 50)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("Search all 84 Figma screens")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        filterChip("All flows", active: selectedArea == nil) {
                            selectedArea = nil
                        }
                        ForEach(HaloFigmaArea.allCases) { area in
                            filterChip(area.rawValue, active: selectedArea == area) {
                                selectedArea = area
                            }
                        }
                    }
                }
                .padding(.vertical, 3)

                ForEach(rows) { screen in
                    NavigationLink {
                        destination(for: screen)
                    } label: {
                        HStack(spacing: 13) {
                            Text(String(format: "%02d", screen.number))
                                .font(HaloMarketplaceDesign.font(14, weight: .bold))
                                .foregroundStyle(HaloMarketplaceDesign.steelBlue)
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(screen.name)
                                    .font(HaloMarketplaceDesign.font(15, weight: .semibold))
                                    .foregroundStyle(HaloMarketplaceDesign.ink)
                                Text(screen.nativePreviewAvailable
                                     ? "SwiftUI · Design preview"
                                     : "Figma spec · SwiftUI port pending")
                                    .font(HaloMarketplaceDesign.font(11))
                                    .foregroundStyle(HaloMarketplaceDesign.slate)
                            }
                            Spacer(minLength: 3)
                            Image(systemName: screen.nativePreviewAvailable
                                  ? "arrow.up.right.square" : "doc.text.magnifyingglass")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(HaloMarketplaceDesign.steelBlue)
                        }
                        .frame(minHeight: 56)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white, in: RoundedRectangle(cornerRadius: 17))
                        .overlay {
                            RoundedRectangle(cornerRadius: 17)
                                .stroke(HaloMarketplaceDesign.border, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(screen.nativePreviewAvailable
                        ? "Open native design preview"
                        : "Open Figma design requirement")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(HaloMarketplaceDesign.pearl.ignoresSafeArea())
        .navigationTitle("HALO Designs")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private func destination(for screen: HaloFigmaScreen) -> some View {
        switch screen.number {
        case 73:
            HaloMarketplaceExploreView()
        case 74:
            HaloMarketplaceExploreView(showsIndustryFilters: true)
        case 75:
            HaloMarketplaceExploreView(startsAsList: true)
        case 76:
            HaloMarketplaceDetailView(job: HaloMarketplacePreview.opportunities[0])
        case 77:
            HaloMarketplaceApplicationPreviewView(
                mode: .apply, job: HaloMarketplacePreview.opportunities[0]
            )
        case 78:
            HaloMarketplaceApplicationPreviewView(
                mode: .assigned, job: HaloMarketplacePreview.opportunities[0]
            )
        case 79:
            HaloMarketplaceExploreView(startsAsList: true, savedOnly: true)
        case 80:
            HaloMarketplaceAvailabilityPreviewView()
        case 81:
            HaloMarketplaceExploreView(industry: .construction)
        case 82:
            HaloMarketplaceExploreView(industry: .property)
        case 83:
            HaloMarketplaceExploreView(industry: .transportation)
        case 84:
            HaloMarketplaceExploreView(industry: .cleaning)
        default:
            notYetImplemented(screen)
        }
    }

    private func notYetImplemented(_ screen: HaloFigmaScreen) -> some View {
        VStack(spacing: 18) {
            HaloMarketplaceWing()
            Text(String(format: "%02d", screen.number))
                .font(HaloMarketplaceDesign.font(44, weight: .bold))
                .foregroundStyle(HaloMarketplaceDesign.steelBlue)
            Text(screen.name)
                .font(HaloMarketplaceDesign.font(23, weight: .bold))
                .foregroundStyle(HaloMarketplaceDesign.ink)
                .multilineTextAlignment(.center)
            Text("This screen is mapped to its exact Figma frame, but is not yet ported to SwiftUI. It is not a functional HALO app screen.")
                .font(HaloMarketplaceDesign.font(13))
                .foregroundStyle(HaloMarketplaceDesign.slate)
                .multilineTextAlignment(.center)
            Link(destination: screen.figmaURL) {
                Label("Open approved Figma frame", systemImage: "arrow.up.right")
                    .font(HaloMarketplaceDesign.font(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(HaloMarketplaceDesign.midnight, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HaloMarketplaceDesign.pearl.ignoresSafeArea())
        .navigationTitle(screen.area.rawValue)
        .preferredColorScheme(.light)
    }

    private func countCard(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(HaloMarketplaceDesign.font(27, weight: .bold))
                .foregroundStyle(HaloMarketplaceDesign.ink)
            Text(title)
                .font(HaloMarketplaceDesign.font(11, weight: .medium))
                .foregroundStyle(HaloMarketplaceDesign.slate)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(.white, in: RoundedRectangle(cornerRadius: 17))
    }

    private func filterChip(
        _ title: String, active: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2), action)
        }) {
            HaloMarketplacePill(title: title, selected: active)
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("HALO · All 84 Figma designs") {
    NavigationStack { HaloFigmaScreenLibraryView() }
}
#endif
