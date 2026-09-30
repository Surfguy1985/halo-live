import Foundation
import UserNotifications

@MainActor
final class HaloNotificationService: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    init() {
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            await refreshAuthorization()
            return granted
        } catch {
            await refreshAuthorization()
            return false
        }
    }

    func scheduleLocalReminder(
        id: String,
        title: String,
        body: String,
        after seconds: TimeInterval
    ) async {
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(seconds, 1),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        try? await UNUserNotificationCenter.current().add(request)
    }

    func clearDelivered() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().setBadgeCount(0)
    }
}
