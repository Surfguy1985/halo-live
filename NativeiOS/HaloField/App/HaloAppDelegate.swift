import UIKit

extension Notification.Name {
    static let haloAPNSDeviceToken = Notification.Name("halo.apns.device-token")
    static let haloAPNSRegistrationFailed = Notification.Name("halo.apns.registration-failed")
    static let haloOpenJob = Notification.Name("halo.push.open-job")
}

final class HaloAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: .haloAPNSDeviceToken, object: token)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let halo = info["halo"] as? [String: Any]
        if let unitID = halo?["unitId"] as? String, !unitID.isEmpty {
            NotificationCenter.default.post(name: .haloOpenJob, object: unitID)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NotificationCenter.default.post(
            name: .haloAPNSRegistrationFailed,
            object: error.localizedDescription
        )
    }
}
