import SwiftUI
import SwiftData

@main
struct HaloFieldApp: App {
    @UIApplicationDelegateAdaptor(HaloAppDelegate.self) private var appDelegate
    @StateObject private var store = JobStore()
    @StateObject private var location = LocationService()
    @StateObject private var session = HaloSessionStore()
    @StateObject private var network = NetworkMonitor()
    @StateObject private var fieldSync = FieldSyncController()
    @StateObject private var notifications = HaloNotificationService()
    @StateObject private var liveActivity = HaloLiveActivityController()
    @StateObject private var realtime = HaloRealtimeService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(location)
                .environmentObject(session)
                .environmentObject(network)
                .environmentObject(fieldSync)
                .environmentObject(notifications)
                .environmentObject(liveActivity)
                .environmentObject(realtime)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    Task { await session.handle(url: url) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .haloAPNSDeviceToken)) { note in
                    guard let token = note.object as? String else { return }
                    Task {
                        await notifications.handleDeviceToken(
                            token,
                            activationToken: session.activationToken
                        )
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .haloAPNSRegistrationFailed)) { note in
                    // The notification service refreshes permission state separately.
                    _ = note.object as? String
                }
                .task(id: session.activationToken) {
                    await notifications.syncRemoteDevice(
                        activationToken: session.activationToken
                    )
                    realtime.start(activationToken: session.activationToken)
                }
        }
        .modelContainer(for: PendingFieldAction.self)
    }
}
