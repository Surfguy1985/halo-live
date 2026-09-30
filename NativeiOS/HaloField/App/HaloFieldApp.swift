import SwiftUI

@main
struct HaloFieldApp: App {
    @StateObject private var store = JobStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.light)
        }
    }
}
