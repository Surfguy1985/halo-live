import SwiftUI
import SwiftData

@main
struct HaloFieldApp: App {
    @StateObject private var store = JobStore()
    @StateObject private var location = LocationService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(location)
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: PendingFieldAction.self)
    }
}