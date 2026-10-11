import Foundation

/// Verified index of every 393×852 screen in the approved HALO Figma file.
/// A catalog entry is a design requirement, NOT an implemented production UI.
enum HaloFigmaArea: String, CaseIterable, Identifiable, Sendable {
    case entry = "Entry & trust"
    case workspace = "Workspace setup"
    case automation = "Workflow builder"
    case operations = "Operations"
    case field = "Field work"
    case commerce = "Commerce"
    case intelligence = "Intelligence & governance"
    case account = "Account"
    case marketplace = "Marketplace"

    var id: Self { self }
}

struct HaloFigmaScreen: Identifiable, Hashable, Sendable {
    let number: Int
    let name: String
    let figmaNode: String
    let area: HaloFigmaArea

    /// True means a SwiftUI design PREVIEW route is available.
    /// It never implies live backend, QA signoff, or production approval.
    let nativePreviewAvailable: Bool

    var id: Int { number }
    var figmaURL: URL {
        URL(string: "https://www.figma.com/design/tsF6XdJRXjS7gTiCGYt4v5?node-id=" +
            figmaNode.replacingOccurrences(of: ":", with: "-"))!
    }
}

enum HaloFigmaScreenCatalog {
    static let screens: [HaloFigmaScreen] = [
        .init(number: 1, name: "Splash", figmaNode: "2:2", area: .entry, nativePreviewAvailable: false),
        .init(number: 2, name: "Welcome to HALO", figmaNode: "2:14", area: .entry, nativePreviewAvailable: false),
        .init(number: 3, name: "Sign in", figmaNode: "2:26", area: .entry, nativePreviewAvailable: false),
        .init(number: 4, name: "Create account", figmaNode: "2:42", area: .entry, nativePreviewAvailable: false),
        .init(number: 5, name: "Passkey sign in", figmaNode: "2:61", area: .entry, nativePreviewAvailable: false),
        .init(number: 6, name: "Verify phone", figmaNode: "2:102", area: .entry, nativePreviewAvailable: false),
        .init(number: 7, name: "Password recovery", figmaNode: "2:115", area: .entry, nativePreviewAvailable: false),
        .init(number: 8, name: "Permissions", figmaNode: "2:134", area: .entry, nativePreviewAvailable: false),
        .init(number: 9, name: "Choose role", figmaNode: "2:162", area: .entry, nativePreviewAvailable: false),
        .init(number: 10, name: "Join workspace", figmaNode: "2:190", area: .workspace, nativePreviewAvailable: false),
        .init(number: 11, name: "Create workspace", figmaNode: "2:231", area: .workspace, nativePreviewAvailable: false),
        .init(number: 12, name: "Choose industry", figmaNode: "2:250", area: .workspace, nativePreviewAvailable: false),
        .init(number: 13, name: "Construction setup", figmaNode: "2:284", area: .workspace, nativePreviewAvailable: false),
        .init(number: 14, name: "Property management setup", figmaNode: "2:303", area: .workspace, nativePreviewAvailable: false),
        .init(number: 15, name: "Transportation setup", figmaNode: "2:322", area: .workspace, nativePreviewAvailable: false),
        .init(number: 16, name: "Field services setup", figmaNode: "2:341", area: .workspace, nativePreviewAvailable: false),
        .init(number: 17, name: "Choose team size", figmaNode: "2:360", area: .workspace, nativePreviewAvailable: false),
        .init(number: 18, name: "Invite teammates", figmaNode: "2:394", area: .workspace, nativePreviewAvailable: false),
        .init(number: 19, name: "Connect integrations", figmaNode: "2:416", area: .workspace, nativePreviewAvailable: false),
        .init(number: 20, name: "Setup complete", figmaNode: "2:444", area: .workspace, nativePreviewAvailable: false),
        .init(number: 21, name: "Template marketplace", figmaNode: "2:485", area: .automation, nativePreviewAvailable: false),
        .init(number: 22, name: "Module library", figmaNode: "2:519", area: .automation, nativePreviewAvailable: false),
        .init(number: 23, name: "Arrangeable block canvas", figmaNode: "2:553", area: .automation, nativePreviewAvailable: false),
        .init(number: 24, name: "Add trigger", figmaNode: "2:587", area: .automation, nativePreviewAvailable: false),
        .init(number: 25, name: "Set condition", figmaNode: "2:615", area: .automation, nativePreviewAvailable: false),
        .init(number: 26, name: "Select action", figmaNode: "2:643", area: .automation, nativePreviewAvailable: false),
        .init(number: 27, name: "Configure fields", figmaNode: "2:671", area: .automation, nativePreviewAvailable: false),
        .init(number: 28, name: "Approval rules", figmaNode: "2:690", area: .automation, nativePreviewAvailable: false),
        .init(number: 29, name: "SLA and escalations", figmaNode: "2:718", area: .automation, nativePreviewAvailable: false),
        .init(number: 30, name: "Workflow simulator", figmaNode: "2:746", area: .automation, nativePreviewAvailable: false),
        .init(number: 31, name: "Publish workflow", figmaNode: "2:780", area: .automation, nativePreviewAvailable: false),
        .init(number: 32, name: "Version history", figmaNode: "2:821", area: .automation, nativePreviewAvailable: false),
        .init(number: 33, name: "Executive home", figmaNode: "2:855", area: .operations, nativePreviewAvailable: false),
        .init(number: 34, name: "Morning briefing", figmaNode: "2:896", area: .operations, nativePreviewAvailable: false),
        .init(number: 35, name: "Live operations map", figmaNode: "2:937", area: .operations, nativePreviewAvailable: false),
        .init(number: 36, name: "Active jobs", figmaNode: "2:977", area: .operations, nativePreviewAvailable: false),
        .init(number: 37, name: "Job details", figmaNode: "2:1024", area: .operations, nativePreviewAvailable: false),
        .init(number: 38, name: "Job timeline", figmaNode: "2:1071", area: .operations, nativePreviewAvailable: false),
        .init(number: 39, name: "Dispatch board", figmaNode: "2:1118", area: .operations, nativePreviewAvailable: false),
        .init(number: 40, name: "Assign crew", figmaNode: "2:1158", area: .operations, nativePreviewAvailable: false),
        .init(number: 41, name: "Crew availability", figmaNode: "2:1186", area: .operations, nativePreviewAvailable: false),
        .init(number: 42, name: "Create job", figmaNode: "2:1208", area: .operations, nativePreviewAvailable: false),
        .init(number: 43, name: "Job checklist", figmaNode: "2:1227", area: .operations, nativePreviewAvailable: false),
        .init(number: 44, name: "Evidence gallery", figmaNode: "2:1274", area: .operations, nativePreviewAvailable: false),
        .init(number: 45, name: "Crew home", figmaNode: "2:1289", area: .field, nativePreviewAvailable: false),
        .init(number: 46, name: "Accept assignment", figmaNode: "2:1330", area: .field, nativePreviewAvailable: false),
        .init(number: 47, name: "Navigation to site", figmaNode: "2:1377", area: .field, nativePreviewAvailable: false),
        .init(number: 48, name: "On site check-in", figmaNode: "2:1417", area: .field, nativePreviewAvailable: false),
        .init(number: 49, name: "Work in progress", figmaNode: "2:1464", area: .field, nativePreviewAvailable: false),
        .init(number: 50, name: "Before photo capture", figmaNode: "2:1511", area: .field, nativePreviewAvailable: false),
        .init(number: 51, name: "Change order request", figmaNode: "2:1526", area: .field, nativePreviewAvailable: false),
        .init(number: 52, name: "Customer signature", figmaNode: "2:1545", area: .field, nativePreviewAvailable: false),
        .init(number: 53, name: "Complete job", figmaNode: "2:1561", area: .field, nativePreviewAvailable: false),
        .init(number: 54, name: "Offline queue", figmaNode: "2:1608", area: .field, nativePreviewAvailable: false),
        .init(number: 55, name: "Quotes and estimates", figmaNode: "2:1655", area: .commerce, nativePreviewAvailable: false),
        .init(number: 56, name: "Estimate editor", figmaNode: "2:1696", area: .commerce, nativePreviewAvailable: false),
        .init(number: 57, name: "Approvals inbox", figmaNode: "2:1715", area: .commerce, nativePreviewAvailable: false),
        .init(number: 58, name: "Invoice preview", figmaNode: "2:1762", area: .commerce, nativePreviewAvailable: false),
        .init(number: 59, name: "Payments", figmaNode: "2:1803", area: .commerce, nativePreviewAvailable: false),
        .init(number: 60, name: "Payouts", figmaNode: "2:1844", area: .commerce, nativePreviewAvailable: false),
        .init(number: 61, name: "Vendor profile", figmaNode: "2:1885", area: .commerce, nativePreviewAvailable: false),
        .init(number: 62, name: "Compliance vault", figmaNode: "2:1927", area: .commerce, nativePreviewAvailable: false),
        .init(number: 63, name: "HALO intelligence", figmaNode: "2:1974", area: .intelligence, nativePreviewAvailable: false),
        .init(number: 64, name: "Ask HALO", figmaNode: "2:2016", area: .intelligence, nativePreviewAvailable: false),
        .init(number: 65, name: "Enforcer overview", figmaNode: "2:2058", area: .intelligence, nativePreviewAvailable: false),
        .init(number: 66, name: "Enforcer rule detail", figmaNode: "2:2099", area: .intelligence, nativePreviewAvailable: false),
        .init(number: 67, name: "Incidents and exceptions", figmaNode: "2:2140", area: .intelligence, nativePreviewAvailable: false),
        .init(number: 68, name: "Revenue at risk", figmaNode: "2:2187", area: .intelligence, nativePreviewAvailable: false),
        .init(number: 69, name: "Analytics", figmaNode: "2:2222", area: .intelligence, nativePreviewAvailable: false),
        .init(number: 70, name: "Activity audit", figmaNode: "2:2257", area: .intelligence, nativePreviewAvailable: false),
        .init(number: 71, name: "Notifications", figmaNode: "2:2304", area: .account, nativePreviewAvailable: false),
        .init(number: 72, name: "Account and preferences", figmaNode: "2:2351", area: .account, nativePreviewAvailable: false),
        .init(number: 73, name: "Open Jobs · Map", figmaNode: "8:2", area: .marketplace, nativePreviewAvailable: true),
        .init(number: 74, name: "Open Jobs · Industry Filters", figmaNode: "8:64", area: .marketplace, nativePreviewAvailable: true),
        .init(number: 75, name: "Open Jobs · List", figmaNode: "8:138", area: .marketplace, nativePreviewAvailable: true),
        .init(number: 76, name: "Job Opportunity · Detail", figmaNode: "8:192", area: .marketplace, nativePreviewAvailable: true),
        .init(number: 77, name: "Job Opportunity · Apply", figmaNode: "8:230", area: .marketplace, nativePreviewAvailable: true),
        .init(number: 78, name: "Job Opportunity · Accepted", figmaNode: "8:268", area: .marketplace, nativePreviewAvailable: true),
        .init(number: 79, name: "Saved Opportunities", figmaNode: "8:306", area: .marketplace, nativePreviewAvailable: true),
        .init(number: 80, name: "Contractor · Available For Work", figmaNode: "8:360", area: .marketplace, nativePreviewAvailable: true),
        .init(number: 81, name: "Industry · Construction Jobs", figmaNode: "8:395", area: .marketplace, nativePreviewAvailable: true),
        .init(number: 82, name: "Industry · Property Jobs", figmaNode: "8:457", area: .marketplace, nativePreviewAvailable: true),
        .init(number: 83, name: "Industry · Transportation Jobs", figmaNode: "8:519", area: .marketplace, nativePreviewAvailable: true),
        .init(number: 84, name: "Industry · Gig Services Jobs", figmaNode: "8:581", area: .marketplace, nativePreviewAvailable: true)
    ]

    static func screen(_ number: Int) -> HaloFigmaScreen? {
        screens.first(where: { $0.number == number })
    }
}
