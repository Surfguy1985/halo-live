import SwiftUI
import SwiftData

@main
struct HaloFieldApp: App {
    @StateObject private var store = JobStore()
    @StateObject private var location = LocationService()
    @StateObject private var session = HaloSessionStore()
    @StateObject private var network = NetworkMonitor()
    @StateObject private var fieldSync = FieldSyncController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(location)
                .environmentObject(session)
                .environmentObject(network)
                .environmentObject(fieldSync)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    session.handle(url: url)
                }
        }
        .modelContainer(for: PendingFieldAction.self)
    }
}
