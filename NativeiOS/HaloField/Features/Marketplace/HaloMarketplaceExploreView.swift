import MapKit
import SwiftUI

/// Native MapKit implementation of Figma screen 73: Open Jobs · Map.
/// This DEBUG integration uses clearly labeled preview opportunities only.
/// It never calls Base44 activation endpoints or pretends a job is assigned.
struct HaloMarketplaceExploreView: View {
    @State private var filter: HaloMarketplaceFilter
    @State private var selectedID: String?
    @State private var showingList: Bool
    @State private var showingFilters: Bool
    @State private var detail: HaloMarketplaceOpportunity?
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 33.055, longitude: -96.746),
            span: MKCoordinateSpan(latitudeDelta: 0.43, longitudeDelta: 0.45)
        )
    )
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Figma 73–75 and industry variants 81–84 reuse one tested MapKit
    /// surface. Each variant sets genuine native state, not a screenshot.
    init(
        industry: HaloMarketplaceIndustry = .all,
        startsAsList: Bool = false,
        savedOnly: Bool = false,
        showsIndustryFilters: Bool = false
    ) {
        _filter = State(initialValue: HaloMarketplaceFilter(
            industry: industry,
            query: "",
            minimumCompensationMinor: 0,
            savedIDs: savedOnly ? ["demo-paint", "demo-construction"] : [],
            savedOnly: savedOnly
        ))
        _showingList = State(initialValue: startsAsList)
        _showingFilters = State(initialValue: showsIndustryFilters)
    }

    private var jobs: [HaloMarketplaceOpportunity] {
        filter.apply(to: HaloMarketplacePreview.opportunities)
    }

    private var featured: HaloMarketplaceOpportunity? {
        jobs.first(where: { $0.id == selectedID }) ?? jobs.first
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            HaloMarketplaceDesign.pearl.ignoresSafeArea()
            if showingList {
                resultsList
            } else {
                mapBody
            }

            VStack(spacing: 0) {
                topChrome
                industryChips
                Spacer(minLength: 0)
                if !showingList {
                    resultSheet
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(.light)
        .sheet(item: $detail) { job in
            HaloMarketplaceDetailView(job: job)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingFilters) {
            filterSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var mapBody: some View {
        Map(position: $cameraPosition) {
            ForEach(jobs) { job in
                Annotation(job.title, coordinate: job.coordinate, anchor: .bottom) {
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.24)) {
                            selectedID = job.id
                        }
                    } label: {
                        Text(job.payout)
                            .font(HaloMarketplaceDesign.font(12, weight: .bold))
                            .foregroundStyle(
                                featured?.id == job.id ? .white : HaloMarketplaceDesign.ink
                            )
                            .padding(.horizontal, 13)
                            .frame(minHeight: 35)
                            .background(
                                featured?.id == job.id
                                    ? HaloMarketplaceDesign.midnight
                                    : Color.white,
                                in: Capsule()
                            )
                            .overlay {
                                Capsule().stroke(HaloMarketplaceDesign.border, lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(job.payout), \(job.title), \(job.locality)")
                }
            }
        }
        .mapStyle(.standard)
        .mapControlVisibility(.hidden)
        .ignoresSafeArea(edges: .bottom)
        .accessibilityLabel("Interactive map of illustrative opportunities near Dallas–Fort Worth")
    }

    private var topChrome: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Explore jobs")
                        .font(HaloMarketplaceDesign.font(28, weight: .bold))
                        .foregroundStyle(HaloMarketplaceDesign.ink)
                    Text("Dallas–Fort Worth · Within 25 miles")
                        .font(HaloMarketplaceDesign.font(12))
                        .foregroundStyle(HaloMarketplaceDesign.slate)
                }
                Spacer()
                HaloMarketplaceWing()
            }

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(HaloMarketplaceDesign.slate)
                TextField("Jobs, skills or places", text: $filter.query)
                    .font(HaloMarketplaceDesign.font(14))
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityLabel("Search opportunities")
                if !filter.query.isEmpty {
                    Button {
                        filter.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel("Clear search")
                }
                Button {
                    showingFilters = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(HaloMarketplaceDesign.midnight)
                }
                .accessibilityLabel("Open opportunity filters")
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 45)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(HaloMarketplaceDesign.border, lineWidth: 1)
            }

            HStack(spacing: 9) {
                Label("DESIGN PREVIEW", systemImage: "eye")
                    .font(HaloMarketplaceDesign.font(10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(HaloMarketplaceDesign.steelBlue)
                Spacer()
                Button {
                    showingList.toggle()
                } label: {
                    Label(showingList ? "Map" : "List", systemImage: showingList ? "map" : "list.bullet")
                        .font(HaloMarketplaceDesign.font(12, weight: .semibold))
                        .foregroundStyle(HaloMarketplaceDesign.ink)
                }
                .accessibilityLabel(showingList ? "Show opportunity map" : "Show opportunity list")
            }
        }
        .padding(.horizontal, 21)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(HaloMarketplaceDesign.pearl.opacity(0.97))
    }

    private var industryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HaloMarketplaceIndustry.allCases) { industry in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.20)) {
                            filter.industry = industry
                        }
                    } label: {
                        HaloMarketplacePill(
                            title: industry.rawValue,
                            selected: filter.industry == industry
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter.industry == industry ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 9)
        .background(HaloMarketplaceDesign.pearl.opacity(0.97))
    }

    @ViewBuilder
    private var resultSheet: some View {
        VStack(alignment: .leading, spacing: 13) {
            Capsule()
                .fill(HaloMarketplaceDesign.border)
                .frame(width: 58, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            HStack {
                Text("\(jobs.count) open jobs nearby")
                    .font(HaloMarketplaceDesign.font(16, weight: .bold))
                    .foregroundStyle(HaloMarketplaceDesign.ink)
                Spacer()
                Button {
                    filter.savedOnly.toggle()
                } label: {
                    Image(systemName: filter.savedOnly ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(HaloMarketplaceDesign.steelBlue)
                }
                .accessibilityLabel(filter.savedOnly ? "Show all jobs" : "Show saved jobs only")
            }

            if let job = featured {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                            Text("ILLUSTRATIVE OPPORTUNITY")
                                .font(HaloMarketplaceDesign.font(10, weight: .semibold))
                                .tracking(0.4)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(HaloMarketplaceDesign.midnight, in: Capsule())
                            Spacer()
                            Button {
                                save(job)
                            } label: {
                                Image(systemName: filter.savedIDs.contains(job.id)
                                      ? "bookmark.fill" : "bookmark")
                                    .foregroundStyle(HaloMarketplaceDesign.steelBlue)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Save opportunity")
                        }
                    Button { detail = job } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(job.title)
                                    .font(HaloMarketplaceDesign.font(16, weight: .semibold))
                                    .foregroundStyle(HaloMarketplaceDesign.ink)
                                Text("\(job.locality) · Preview listing")
                                    .font(HaloMarketplaceDesign.font(12))
                                    .foregroundStyle(HaloMarketplaceDesign.slate)
                            }
                            Spacer(minLength: 6)
                            Text(job.payout)
                                .font(HaloMarketplaceDesign.font(21, weight: .bold))
                                .foregroundStyle(HaloMarketplaceDesign.earningGreen)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Open opportunity details; job is preview only")
                }
            } else {
                Text("No jobs match your filters. Try another industry.")
                    .font(HaloMarketplaceDesign.font(13))
                    .foregroundStyle(HaloMarketplaceDesign.slate)
                    .padding(.vertical, 18)
            }
        }
        .padding(17)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(HaloMarketplaceDesign.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 18, y: 9)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Color.clear.frame(height: 248)
                ForEach(jobs) { job in
                    Button { detail = job } label: {
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(HaloMarketplaceDesign.mapCanvas)
                                .frame(width: 54, height: 54)
                                .overlay {
                                    Image(systemName: "briefcase")
                                        .foregroundStyle(HaloMarketplaceDesign.steelBlue)
                                }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(job.title)
                                    .font(HaloMarketplaceDesign.font(15, weight: .semibold))
                                    .foregroundStyle(HaloMarketplaceDesign.ink)
                                Text("\(job.locality) · \(job.industry.rawValue)")
                                    .font(HaloMarketplaceDesign.font(12))
                                    .foregroundStyle(HaloMarketplaceDesign.slate)
                            }
                            Spacer()
                            Text(job.payout)
                                .font(HaloMarketplaceDesign.font(15, weight: .bold))
                                .foregroundStyle(HaloMarketplaceDesign.earningGreen)
                        }
                        .padding(15)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(HaloMarketplaceDesign.pearl)
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Minimum compensation") {
                    Picker("Pay range", selection: $filter.minimumCompensationMinor) {
                        Text("Any").tag(0)
                        Text("$250+").tag(25_000)
                        Text("$500+").tag(50_000)
                        Text("$750+").tag(75_000)
                    }
                }
                Section {
                    Toggle("Saved opportunities only", isOn: $filter.savedOnly)
                        .tint(HaloMarketplaceDesign.steelBlue)
                }
                Section {
                    Text("All jobs shown in this preview are illustrative. Verified live listings require separate authentication and backend approval.")
                        .font(.footnote)
                        .foregroundStyle(HaloMarketplaceDesign.slate)
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingFilters = false }
                }
            }
        }
        .tint(HaloMarketplaceDesign.steelBlue)
    }

    private func save(_ job: HaloMarketplaceOpportunity) {
        if filter.savedIDs.contains(job.id) {
            filter.savedIDs.remove(job.id)
        } else {
            filter.savedIDs.insert(job.id)
        }
    }
}

#if DEBUG
#Preview("HALO · Figma 73 · Open Jobs Map") {
    NavigationStack {
        HaloMarketplaceExploreView()
    }
}
#endif
