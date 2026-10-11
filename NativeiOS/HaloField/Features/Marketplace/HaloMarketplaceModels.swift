import CoreLocation
import Foundation

enum HaloMarketplaceIndustry: String, CaseIterable, Identifiable {
    case all = "All"
    case construction = "Construction"
    case property = "Property"
    case transportation = "Transport"
    case hospitality = "Hospitality"
    case cleaning = "Cleaning"
    case security = "Security"
    case other = "Other"

    var id: String { rawValue }

    var apiValue: String? {
        switch self {
        case .all: nil
        case .transportation: "transportation"
        default: rawValue.lowercased()
        }
    }
}

/// The marketplace domain is separate from already ASSIGNED field jobs.
/// A request receipt is never an assignment, work authorization, or payout.
struct HaloMarketplaceOpportunity: Identifiable, Hashable {
    let id: String
    let publisherOrganizationID: String
    let title: String
    let industry: HaloMarketplaceIndustry
    let locality: String
    let latitude: Double
    let longitude: Double
    let compensationMinor: Int
    let customerName: String
    let customerVerified: Bool
    let scope: [String]
    let scheduledStart: Date
    let durationMinutes: Int
    let mediaURLs: [URL]
    let previewOnly: Bool

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var payout: String {
        let dollars = Double(compensationMinor) / 100
        return dollars.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    var validMapPosition: Bool {
        latitude.isFinite && longitude.isFinite &&
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.publisherOrganizationID == rhs.publisherOrganizationID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(publisherOrganizationID)
    }
}

enum HaloMarketplacePreview {
    // Illustrative opportunities are never promoted to real listings.
    static let opportunities: [HaloMarketplaceOpportunity] = [
        sample("demo-paint", title: "Apartment paint + prep", industry: .property,
               locality: "Plano, TX", lat: 33.0198, lon: -96.6989, dollars: 420,
               scope: ["Interior paint and surface preparation", "Materials provided"]),
        sample("demo-construction", title: "Framing crew · 1 day", industry: .construction,
               locality: "Frisco, TX", lat: 33.1535, lon: -96.8240, dollars: 780,
               scope: ["Assist with interior framing", "Safety equipment required"]),
        sample("demo-delivery", title: "Scheduled materials delivery", industry: .transportation,
               locality: "Richardson, TX", lat: 32.9483, lon: -96.7299, dollars: 180,
               scope: ["Scheduled route", "Suitable vehicle required"]),
        sample("demo-security", title: "Venue security shift", industry: .security,
               locality: "Addison, TX", lat: 32.9618, lon: -96.8292, dollars: 325,
               scope: ["On-site access control", "Required credentials verified"]),
        sample("demo-service", title: "Restaurant deep clean", industry: .cleaning,
               locality: "McKinney, TX", lat: 33.1972, lon: -96.6397, dollars: 560,
               scope: ["Kitchen and common-area cleaning", "Commercial cleaning experience"]),
    ]

    private static func sample(
        _ id: String, title: String, industry: HaloMarketplaceIndustry,
        locality: String, lat: Double, lon: Double, dollars: Int,
        scope: [String]
    ) -> HaloMarketplaceOpportunity {
        HaloMarketplaceOpportunity(
            id: id,
            publisherOrganizationID: "demo-publisher",
            title: title,
            industry: industry,
            locality: locality,
            latitude: lat,
            longitude: lon,
            compensationMinor: dollars * 100,
            customerName: "Illustrative customer",
            customerVerified: false,
            scope: scope,
            scheduledStart: Date(timeIntervalSince1970: 1_781_800_000),
            durationMinutes: 180,
            mediaURLs: [],
            previewOnly: true
        )
    }
}

struct HaloMarketplaceFilter {
    var industry: HaloMarketplaceIndustry = .all
    var query: String = ""
    var minimumCompensationMinor = 0
    var savedIDs: Set<String> = []
    var savedOnly = false

    func apply(to jobs: [HaloMarketplaceOpportunity]) -> [HaloMarketplaceOpportunity] {
        jobs.filter { job in
            (industry == .all || industry == job.industry) &&
            (query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
             (job.title + " " + job.locality + " " + job.industry.rawValue)
                .localizedStandardContains(query)) &&
            job.compensationMinor >= minimumCompensationMinor &&
            (!savedOnly || savedIDs.contains(job.id)) &&
            job.validMapPosition
        }
    }
}
